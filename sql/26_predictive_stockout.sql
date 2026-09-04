/* ============================================================================
   SupplyChainIQ - PHASE 10b : PREDICTIVE STOCKOUT EARLY WARNING (POC)
   FILE    : 26_predictive_stockout.sql
   PURPOSE : Additive, read-only Predictive Stockout Early Warning backend
             using SNOWFLAKE.ML.FORECAST. Identifies PART_ID + PLANT_ID
             combinations likely to run short of inventory within the next
             14 days based on historical ACTUAL_DEMAND_QTY, for grains that
             do NOT already have a confirmed Risk Radar entry.

   SAFETY  : Creates only new objects in the existing, additive RISK schema.
             It does not modify CURATED.DEMAND, CURATED.INVENTORY_SNAPSHOT,
             CURATED.CUSTOMER_ORDER_LINE, CURATED.SHIPMENT, the confirmed
             RISK.SUPPLY_CHAIN_RISK_CANDIDATES / RISK.SUPPLY_CHAIN_RISK_RANKING
             views, DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS, WORKFLOW,
             ACTION, the Cortex Agent, Semantic View, Cortex Search, or the
             Streamlit application.

   DOUBLE-COUNTING PREVENTION: forecast demand is never added to confirmed
   open-order demand. CONFIRMED_DEMAND_QUANTITY is exposed for transparency
   only. Any PART_ID + PLANT_ID already present in
   RISK.SUPPLY_CHAIN_RISK_CANDIDATES is excluded from
   RISK.FORECASTED_STOCKOUT_RISK - confirmed risk always takes precedence.

   MODEL TRAINING NOTE: training a 2,000-series SNOWFLAKE.ML.FORECAST model
   on an X-Small warehouse did not complete within a 20-minute client
   timeout. This file trains on whatever warehouse is currently in use
   (COMPUTE_WH by default); if training is slow, temporarily resize
   COMPUTE_WH (e.g. to MEDIUM) before running this file and resize back down
   afterward. This is a one-time training cost - persisted forecast results
   are reused by Streamlit, not regenerated per page refresh.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/*
Training input for the multi-series forecast. IMPORTANT: only SERIES_ID,
DEMAND_DATE, and ACTUAL_DEMAND_QTY are exposed. Including PART_ID/PLANT_ID
as separate columns causes SNOWFLAKE.ML.FORECAST to treat them as exogenous
features and the FORECAST method then requires future exogenous data that
does not exist for this POC - PART_ID/PLANT_ID are recovered later from
SERIES_ID via SPLIT_PART.
*/
CREATE OR REPLACE VIEW RISK.DEMAND_FORECAST_TRAINING_INPUT
COMMENT = 'Phase 10b: read-only training input for the Predictive Stockout multi-series forecast. Only SERIES_ID, DEMAND_DATE, ACTUAL_DEMAND_QTY are exposed so SNOWFLAKE.ML.FORECAST does not treat PART_ID/PLANT_ID as exogenous features. Sourced 1:1 from CURATED.DEMAND. Target is ACTUAL_DEMAND_QTY (realized demand), never the legacy FORECAST_QTY column.'
AS
SELECT
    PART_ID || '|' || PLANT_ID AS SERIES_ID,
    DEMAND_DATE,
    ACTUAL_DEMAND_QTY
FROM CURATED.DEMAND;

/*
One multi-series model trained on all 60 days of available history
(2,000 series x 60 daily observations = 120,000 rows). Do not create one
model per series.
*/
CREATE SNOWFLAKE.ML.FORECAST IF NOT EXISTS RISK.SUPPLY_CHAIN_DEMAND_FORECAST_MODEL(
  INPUT_DATA => TABLE(RISK.DEMAND_FORECAST_TRAINING_INPUT),
  SERIES_COLNAME => 'SERIES_ID',
  TIMESTAMP_COLNAME => 'DEMAND_DATE',
  TARGET_COLNAME => 'ACTUAL_DEMAND_QTY'
);

/*
Persist per-series SMAPE from the model's own out-of-sample evaluation
metrics. Used as a quality gate: series with SMAPE > 0.5 are excluded from
RISK.FORECASTED_STOCKOUT_RISK so a poorly-fit forecast is never surfaced as
an early warning.
*/
CREATE OR REPLACE TABLE RISK.FORECAST_MODEL_QUALITY
COMMENT = 'Phase 10b: persisted per-series SMAPE from SUPPLY_CHAIN_DEMAND_FORECAST_MODEL!SHOW_EVALUATION_METRICS(), used as a quality gate to exclude poorly-fit series from RISK.FORECASTED_STOCKOUT_RISK.'
AS
SELECT
  SPLIT_PART(SERIES, '|', 1) AS PART_ID,
  SPLIT_PART(SERIES, '|', 2) AS PLANT_ID,
  METRIC_VALUE AS SMAPE
FROM TABLE(RISK.SUPPLY_CHAIN_DEMAND_FORECAST_MODEL!SHOW_EVALUATION_METRICS())
WHERE ERROR_METRIC = 'SMAPE';

/*
Generate and persist a 14-day daily forecast once. Streamlit (and any other
consumer) reads this table instead of retraining or re-running !FORECAST on
every page refresh.
*/
CREATE OR REPLACE TABLE RISK.FORECASTED_DEMAND
COMMENT = 'Phase 10b: persisted 14-day daily demand forecast from SUPPLY_CHAIN_DEMAND_FORECAST_MODEL. Generated once; not retrained on Streamlit refresh.'
AS
SELECT
  SPLIT_PART(SERIES, '|', 1) AS PART_ID,
  SPLIT_PART(SERIES, '|', 2) AS PLANT_ID,
  TS AS FORECAST_DATE,
  FORECAST AS FORECAST_VALUE,
  LOWER_BOUND,
  UPPER_BOUND,
  'SUPPLY_CHAIN_DEMAND_FORECAST_MODEL' AS MODEL_NAME,
  CURRENT_TIMESTAMP() AS GENERATED_AT,
  (SELECT DATASET_ANCHOR_DATE FROM PUBLIC.DATASET_METADATA ORDER BY VERSION DESC LIMIT 1) AS REFERENCE_DATE
FROM TABLE(RISK.SUPPLY_CHAIN_DEMAND_FORECAST_MODEL!FORECAST(FORECASTING_PERIODS => 14));

/*
Final read-only Predictive Stockout Early Warning view.

Logic:
  - CURRENT_USABLE_QUANTITY = GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0),
    same latest-inventory-snapshot logic used by the confirmed Risk Radar.
  - EXPECTED_INBOUND_QUANTITY comes only from SHIPMENT rows that are
    IN_TRANSIT or PLANNED (ACTUAL_DELIVERY_DATE IS NULL - not yet arrived)
    with PROJECTED_DELIVERY_DATE inside the 14-day horizon. DELIVERED and
    PARTIAL shipments are excluded because they are already reflected in
    current inventory; CANCELLED purchase orders never create a shipment
    row in this model and so are excluded implicitly.
  - PREDICTED_STOCKOUT_DATE is the first forecast date at which cumulative
    forecast demand exceeds current usable inventory plus cumulative
    eligible inbound arriving by that date (a real daily walk via window
    functions - never total-shortage / average-demand).
  - FORECASTED_SHORTAGE_QUANTITY = GREATEST(FORECAST_DEMAND_14D -
    CURRENT_USABLE_QUANTITY - EXPECTED_INBOUND_QUANTITY, 0). Confirmed
    open-order demand (CONFIRMED_DEMAND_QUANTITY) is never added to this
    calculation - it is exposed as a transparency-only field.
  - Confirmed-risk suppression: any PART_ID + PLANT_ID already present in
    RISK.SUPPLY_CHAIN_RISK_CANDIDATES is excluded here. Confirmed risk
    always takes precedence; this view finds NEW early-warning cases only.
  - Model-quality gate: series with SMAPE > 0.5 (from
    RISK.FORECAST_MODEL_QUALITY) are excluded.
  - No severity score is computed or reused here by design (see file 27
    validation and Phase 1 design notes) - only transparent, explainable
    fields (DAYS_TO_PREDICTED_STOCKOUT, PREDICTED_STOCKOUT_DATE,
    FORECASTED_SHORTAGE_QUANTITY, prediction bounds) are exposed.
*/
CREATE OR REPLACE VIEW RISK.FORECASTED_STOCKOUT_RISK
COMMENT = 'Phase 10b: read-only Predictive Stockout Early Warning. Identifies PART_ID+PLANT_ID combinations with a likely future shortage per SNOWFLAKE.ML.FORECAST demand forecasts, for grains that do NOT already have a confirmed Risk Radar entry. Confirmed demand is transparency-only and is never added to forecast demand (avoids double counting). Excludes series with poor model fit (SMAPE > 0.5).'
AS
WITH ref AS (
    SELECT DATASET_ANCHOR_DATE AS REFERENCE_DATE
    FROM PUBLIC.DATASET_METADATA
    ORDER BY VERSION DESC
    LIMIT 1
),
latest_inventory AS (
    SELECT
        i.PART_ID,
        i.PLANT_ID,
        i.AVAILABLE_QTY,
        i.SAFETY_STOCK_QTY,
        GREATEST(i.AVAILABLE_QTY - i.SAFETY_STOCK_QTY, 0) AS USABLE_QTY
    FROM CURATED.INVENTORY_SNAPSHOT i
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY i.PART_ID, i.PLANT_ID
        ORDER BY i.SNAPSHOT_DATE DESC
    ) = 1
),
confirmed_demand AS (
    SELECT
        c.PART_ID,
        c.PLANT_ID,
        SUM(GREATEST(c.ORDERED_QTY - c.FULFILLED_QTY, 0)) AS CONFIRMED_DEMAND_QUANTITY
    FROM CURATED.CUSTOMER_ORDER_LINE c
    CROSS JOIN ref
    WHERE c.ORDER_STATUS NOT IN ('CANCELLED', 'FULFILLED')
      AND c.DUE_DATE BETWEEN ref.REFERENCE_DATE AND DATEADD(day, 14, ref.REFERENCE_DATE)
    GROUP BY c.PART_ID, c.PLANT_ID
),
eligible_inbound AS (
    SELECT
        s.PART_ID,
        s.PLANT_ID,
        s.PROJECTED_DELIVERY_DATE AS ARRIVAL_DATE,
        SUM(s.SHIPPED_QTY) AS INBOUND_QTY
    FROM CURATED.SHIPMENT s
    CROSS JOIN ref
    WHERE s.SHIPMENT_STATUS IN ('IN_TRANSIT', 'PLANNED')
      AND s.ACTUAL_DELIVERY_DATE IS NULL
      AND s.PROJECTED_DELIVERY_DATE BETWEEN ref.REFERENCE_DATE AND DATEADD(day, 14, ref.REFERENCE_DATE)
    GROUP BY s.PART_ID, s.PLANT_ID, s.PROJECTED_DELIVERY_DATE
),
forecast_daily AS (
    SELECT
        f.PART_ID,
        f.PLANT_ID,
        f.FORECAST_DATE::DATE AS FORECAST_DATE,
        f.FORECAST_VALUE,
        f.LOWER_BOUND,
        f.UPPER_BOUND,
        f.MODEL_NAME,
        f.GENERATED_AT,
        f.REFERENCE_DATE
    FROM RISK.FORECASTED_DEMAND f
),
daily_walk AS (
    SELECT
        fd.PART_ID,
        fd.PLANT_ID,
        fd.FORECAST_DATE,
        fd.FORECAST_VALUE,
        fd.LOWER_BOUND,
        fd.UPPER_BOUND,
        SUM(fd.FORECAST_VALUE) OVER (
            PARTITION BY fd.PART_ID, fd.PLANT_ID ORDER BY fd.FORECAST_DATE
        ) AS CUM_FORECAST_DEMAND,
        SUM(COALESCE(ei.INBOUND_QTY, 0)) OVER (
            PARTITION BY fd.PART_ID, fd.PLANT_ID ORDER BY fd.FORECAST_DATE
        ) AS CUM_ELIGIBLE_INBOUND
    FROM forecast_daily fd
    LEFT JOIN eligible_inbound ei
      ON ei.PART_ID = fd.PART_ID
     AND ei.PLANT_ID = fd.PLANT_ID
     AND ei.ARRIVAL_DATE = fd.FORECAST_DATE
),
net_position AS (
    SELECT
        dw.*,
        li.USABLE_QTY,
        (dw.CUM_FORECAST_DEMAND - li.USABLE_QTY - dw.CUM_ELIGIBLE_INBOUND) AS NET_POSITION
    FROM daily_walk dw
    JOIN latest_inventory li
      ON li.PART_ID = dw.PART_ID
     AND li.PLANT_ID = dw.PLANT_ID
),
stockout_date AS (
    SELECT
        PART_ID,
        PLANT_ID,
        MIN(FORECAST_DATE) AS PREDICTED_STOCKOUT_DATE
    FROM net_position
    WHERE NET_POSITION > 0
    GROUP BY PART_ID, PLANT_ID
),
totals AS (
    SELECT
        PART_ID,
        PLANT_ID,
        MIN(FORECAST_DATE) AS FORECAST_START_DATE,
        MAX(FORECAST_DATE) AS FORECAST_END_DATE,
        SUM(FORECAST_VALUE) AS FORECAST_DEMAND_QUANTITY,
        SUM(LOWER_BOUND) AS LOWER_PREDICTION_BOUND,
        SUM(UPPER_BOUND) AS UPPER_PREDICTION_BOUND
    FROM forecast_daily
    GROUP BY PART_ID, PLANT_ID
),
total_inbound AS (
    SELECT PART_ID, PLANT_ID, SUM(INBOUND_QTY) AS EXPECTED_INBOUND_QUANTITY
    FROM eligible_inbound
    GROUP BY PART_ID, PLANT_ID
)
SELECT
    t.PART_ID,
    part.PART_DESCRIPTION,
    t.PLANT_ID,
    plant.PLANT_NAME,
    t.FORECAST_START_DATE,
    t.FORECAST_END_DATE,
    li.AVAILABLE_QTY AS CURRENT_AVAILABLE_QUANTITY,
    li.SAFETY_STOCK_QTY AS SAFETY_STOCK,
    li.USABLE_QTY AS CURRENT_USABLE_QUANTITY,
    COALESCE(cd.CONFIRMED_DEMAND_QUANTITY, 0) AS CONFIRMED_DEMAND_QUANTITY,
    t.FORECAST_DEMAND_QUANTITY,
    COALESCE(ti.EXPECTED_INBOUND_QUANTITY, 0) AS EXPECTED_INBOUND_QUANTITY,
    GREATEST(t.FORECAST_DEMAND_QUANTITY - li.USABLE_QTY - COALESCE(ti.EXPECTED_INBOUND_QUANTITY, 0), 0) AS FORECASTED_SHORTAGE_QUANTITY,
    sd.PREDICTED_STOCKOUT_DATE,
    DATEDIFF(day, ref.REFERENCE_DATE, sd.PREDICTED_STOCKOUT_DATE) AS DAYS_TO_PREDICTED_STOCKOUT,
    t.LOWER_PREDICTION_BOUND,
    t.UPPER_PREDICTION_BOUND,
    'SUPPLY_CHAIN_DEMAND_FORECAST_MODEL' AS MODEL_NAME,
    CURRENT_TIMESTAMP() AS GENERATED_AT,
    ref.REFERENCE_DATE
FROM totals t
CROSS JOIN ref
JOIN latest_inventory li
  ON li.PART_ID = t.PART_ID AND li.PLANT_ID = t.PLANT_ID
JOIN RISK.FORECAST_MODEL_QUALITY q
  ON q.PART_ID = t.PART_ID AND q.PLANT_ID = t.PLANT_ID
LEFT JOIN confirmed_demand cd
  ON cd.PART_ID = t.PART_ID AND cd.PLANT_ID = t.PLANT_ID
LEFT JOIN total_inbound ti
  ON ti.PART_ID = t.PART_ID AND ti.PLANT_ID = t.PLANT_ID
LEFT JOIN stockout_date sd
  ON sd.PART_ID = t.PART_ID AND sd.PLANT_ID = t.PLANT_ID
JOIN CURATED.PART part
  ON part.PART_ID = t.PART_ID
JOIN CURATED.PLANT plant
  ON plant.PLANT_ID = t.PLANT_ID
WHERE q.SMAPE <= 0.5
  AND sd.PREDICTED_STOCKOUT_DATE IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM RISK.SUPPLY_CHAIN_RISK_CANDIDATES rc
      WHERE rc.PART_ID = t.PART_ID AND rc.PLANT_ID = t.PLANT_ID
  );

SELECT 'Phase 10b / 26_predictive_stockout.sql complete' AS STATUS;
