/* ============================================================================
   SupplyChainIQ - PHASE 10 : PROACTIVE RISK INTELLIGENCE
   FILE    : 24_risk_intelligence.sql
   PURPOSE : Add read-only, deterministic risk candidates and ranking views.

   SAFETY  : Creates only views in the additive RISK schema. It does not
             modify source data, CURATED, DECISION, WORKFLOW, ACTION, the
             Cortex Agent, Semantic View, or Cortex Search. Recommendation
             evaluation remains in DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

CREATE SCHEMA IF NOT EXISTS RISK
COMMENT = 'Phase 10 deterministic, read-only supply-chain risk intelligence.';

/*
Risk grain: primary active Supplier x Part x destination Plant. The source
supplier is deterministically selected from the active, current supplier-part
agreement (primary first, then SUPPLIER_ID). This is the same identifier grain
accepted by DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS. A risk is emitted
only when the evaluator-aligned 14-day open-order requirement exceeds usable
inventory (available inventory less safety stock).
*/
CREATE OR REPLACE VIEW RISK.SUPPLY_CHAIN_RISK_CANDIDATES
COMMENT = 'One deterministic shortage-risk candidate per primary active SUPPLIER_ID x PART_ID x PLANT_ID. Uses latest inventory and 14-day open customer-order demand at the dataset reference date.'
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
open_demand AS (
    SELECT
        c.PART_ID,
        c.PLANT_ID,
        SUM(GREATEST(c.ORDERED_QTY - c.FULFILLED_QTY, 0)) AS REQUIREMENT_QTY,
        MIN(c.DUE_DATE) AS FIRST_CUSTOMER_DUE_DATE,
        COUNT(*) AS AFFECTED_ORDER_LINES,
        SUM(c.ORDER_VALUE) AS REVENUE_EXPOSURE
    FROM CURATED.CUSTOMER_ORDER_LINE c
    CROSS JOIN ref
    WHERE c.ORDER_STATUS NOT IN ('CANCELLED', 'FULFILLED')
      AND c.DUE_DATE BETWEEN ref.REFERENCE_DATE AND DATEADD(day, 14, ref.REFERENCE_DATE)
    GROUP BY c.PART_ID, c.PLANT_ID
),
source_supplier AS (
    SELECT
        sp.PART_ID,
        sp.SUPPLIER_ID,
        s.SUPPLIER_NAME
    FROM CURATED.SUPPLIER_PART sp
    JOIN CURATED.SUPPLIER s
      ON s.SUPPLIER_ID = sp.SUPPLIER_ID
    CROSS JOIN ref
    WHERE s.VENDOR_STATUS = 'Active'
      AND sp.VALID_FROM <= ref.REFERENCE_DATE
      AND sp.VALID_TO >= ref.REFERENCE_DATE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sp.PART_ID
        ORDER BY IFF(sp.IS_PRIMARY_SUPPLIER, 0, 1), sp.SUPPLIER_ID
    ) = 1
),
delayed_shipment AS (
    SELECT
        s.SUPPLIER_ID,
        s.PART_ID,
        s.PLANT_ID,
        s.SHIPMENT_ID,
        s.SHIPMENT_STATUS,
        DATEDIFF(day, p.PROMISED_DATE, s.PROJECTED_DELIVERY_DATE) AS DELAY_DAYS,
        s.PROJECTED_DELIVERY_DATE AS EXPECTED_ARRIVAL_DATE
    FROM CURATED.SHIPMENT s
    JOIN CURATED.PURCHASE_ORDER_LINE p
      ON p.PO_NUMBER = s.PO_NUMBER
     AND p.PO_LINE_NUMBER = s.PO_LINE_NUMBER
    WHERE s.SHIPMENT_STATUS = 'IN_TRANSIT'
      AND s.PROJECTED_DELIVERY_DATE > p.PROMISED_DATE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY s.SUPPLIER_ID, s.PART_ID, s.PLANT_ID
        ORDER BY s.PROJECTED_DELIVERY_DATE, s.SHIPMENT_ID
    ) = 1
),
supplier_otd AS (
    SELECT
        s.SUPPLIER_ID,
        SUM(IFF(s.ACTUAL_DELIVERY_DATE <= p.PROMISED_DATE, 1, 0))
          / NULLIF(COUNT(*), 0) AS SUPPLIER_OTD_PERCENT
    FROM CURATED.SHIPMENT s
    JOIN CURATED.PURCHASE_ORDER_LINE p
      ON p.PO_NUMBER = s.PO_NUMBER
     AND p.PO_LINE_NUMBER = s.PO_LINE_NUMBER
    WHERE s.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
      AND s.ACTUAL_DELIVERY_DATE IS NOT NULL
      AND p.PO_STATUS <> 'CANCELLED'
    GROUP BY s.SUPPLIER_ID
)
SELECT
    'RISK::' || ss.SUPPLIER_ID || '::' || li.PART_ID || '::' || li.PLANT_ID AS RISK_ID,
    ss.SUPPLIER_ID,
    ss.SUPPLIER_NAME,
    li.PART_ID,
    part.PART_DESCRIPTION,
    li.PLANT_ID,
    plant.PLANT_NAME,
    li.AVAILABLE_QTY AS AVAILABLE_QUANTITY,
    li.SAFETY_STOCK_QTY AS SAFETY_STOCK,
    li.USABLE_QTY AS USABLE_QUANTITY,
    od.REQUIREMENT_QTY AS REQUIREMENT_QUANTITY,
    GREATEST(od.REQUIREMENT_QTY - li.USABLE_QTY, 0) AS SHORTAGE_QUANTITY,
    od.FIRST_CUSTOMER_DUE_DATE,
    od.AFFECTED_ORDER_LINES,
    od.REVENUE_EXPOSURE,
    ds.SHIPMENT_ID AS DELAYED_SHIPMENT_ID,
    ds.SHIPMENT_STATUS,
    ds.DELAY_DAYS,
    ds.EXPECTED_ARRIVAL_DATE,
    so.SUPPLIER_OTD_PERCENT,
    ref.REFERENCE_DATE
FROM latest_inventory li
JOIN open_demand od
  ON od.PART_ID = li.PART_ID
 AND od.PLANT_ID = li.PLANT_ID
JOIN source_supplier ss
  ON ss.PART_ID = li.PART_ID
JOIN CURATED.PART part
  ON part.PART_ID = li.PART_ID
JOIN CURATED.PLANT plant
  ON plant.PLANT_ID = li.PLANT_ID
CROSS JOIN ref
LEFT JOIN delayed_shipment ds
  ON ds.SUPPLIER_ID = ss.SUPPLIER_ID
 AND ds.PART_ID = li.PART_ID
 AND ds.PLANT_ID = li.PLANT_ID
LEFT JOIN supplier_otd so
  ON so.SUPPLIER_ID = ss.SUPPLIER_ID
WHERE GREATEST(od.REQUIREMENT_QTY - li.USABLE_QTY, 0) > 0;

/*
Score formula (0..100):
  shortage  0..45 = 45 * shortage / requirement
  urgency   0..20 = due <=3 / <=7 / <=14 days: 20 / 15 / 8
  revenue   0..15 = 15 * exposure / maximum candidate exposure
  shipment  0..10 = min(delayed days, 10), when a delayed in-transit shipment exists
  supplier  0..10 = 10 * (1 - governed historical supplier OTD), when available

The revenue component is normalized against the current candidate set, not a
fabricated currency threshold. All other components are directly bounded by
their published limits. Ties are resolved by RISK_ID.
*/
CREATE OR REPLACE VIEW RISK.SUPPLY_CHAIN_RISK_RANKING
COMMENT = 'Deterministic ranked shortage risks with explainable 100-point component scores. Severity: CRITICAL >=70, HIGH >=50, MEDIUM >=30, LOW <30.'
AS
WITH component_base AS (
    SELECT
        c.*,
        LEAST(45, 45 * c.SHORTAGE_QUANTITY / NULLIF(c.REQUIREMENT_QUANTITY, 0)) AS SHORTAGE_SCORE,
        CASE
            WHEN c.FIRST_CUSTOMER_DUE_DATE <= DATEADD(day, 3, c.REFERENCE_DATE) THEN 20
            WHEN c.FIRST_CUSTOMER_DUE_DATE <= DATEADD(day, 7, c.REFERENCE_DATE) THEN 15
            WHEN c.FIRST_CUSTOMER_DUE_DATE <= DATEADD(day, 14, c.REFERENCE_DATE) THEN 8
            ELSE 0
        END AS URGENCY_SCORE,
        IFF(c.DELAYED_SHIPMENT_ID IS NULL, 0, LEAST(COALESCE(c.DELAY_DAYS, 0), 10)) AS SHIPMENT_SCORE,
        IFF(c.SUPPLIER_OTD_PERCENT IS NULL, 0, LEAST(10, GREATEST(0, 10 * (1 - c.SUPPLIER_OTD_PERCENT)))) AS SUPPLIER_SCORE
    FROM RISK.SUPPLY_CHAIN_RISK_CANDIDATES c
),
scored AS (
    SELECT
        cb.*,
        IFF(
            MAX(cb.REVENUE_EXPOSURE) OVER () > 0,
            15 * cb.REVENUE_EXPOSURE / MAX(cb.REVENUE_EXPOSURE) OVER (),
            0
        ) AS REVENUE_SCORE
    FROM component_base cb
),
totaled AS (
    SELECT
        s.*,
        ROUND(s.SHORTAGE_SCORE + s.URGENCY_SCORE + s.REVENUE_SCORE + s.SHIPMENT_SCORE + s.SUPPLIER_SCORE, 2) AS RISK_SCORE
    FROM scored s
)
SELECT
    RISK_ID,
    RANK() OVER (ORDER BY RISK_SCORE DESC, RISK_ID) AS RISK_RANK,
    RISK_SCORE,
    CASE
        WHEN RISK_SCORE >= 70 THEN 'CRITICAL'
        WHEN RISK_SCORE >= 50 THEN 'HIGH'
        WHEN RISK_SCORE >= 30 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS SEVERITY,
    SUPPLIER_ID,
    SUPPLIER_NAME,
    PART_ID,
    PART_DESCRIPTION,
    PLANT_ID,
    PLANT_NAME,
    AVAILABLE_QUANTITY,
    SAFETY_STOCK,
    USABLE_QUANTITY,
    REQUIREMENT_QUANTITY,
    SHORTAGE_QUANTITY,
    FIRST_CUSTOMER_DUE_DATE,
    AFFECTED_ORDER_LINES,
    REVENUE_EXPOSURE,
    DELAYED_SHIPMENT_ID,
    SHIPMENT_STATUS,
    DELAY_DAYS,
    EXPECTED_ARRIVAL_DATE,
    SUPPLIER_OTD_PERCENT,
    ROUND(SHORTAGE_SCORE, 2) AS SHORTAGE_SCORE,
    ROUND(URGENCY_SCORE, 2) AS URGENCY_SCORE,
    ROUND(REVENUE_SCORE, 2) AS REVENUE_SCORE,
    ROUND(SHIPMENT_SCORE, 2) AS SHIPMENT_SCORE,
    ROUND(SUPPLIER_SCORE, 2) AS SUPPLIER_SCORE,
    CASE
        WHEN SHORTAGE_SCORE >= URGENCY_SCORE
         AND SHORTAGE_SCORE >= REVENUE_SCORE
         AND SHORTAGE_SCORE >= SHIPMENT_SCORE
         AND SHORTAGE_SCORE >= SUPPLIER_SCORE
            THEN 'Open customer demand exceeds inventory available above safety stock.'
        WHEN URGENCY_SCORE >= REVENUE_SCORE
         AND URGENCY_SCORE >= SHIPMENT_SCORE
         AND URGENCY_SCORE >= SUPPLIER_SCORE
            THEN 'Affected customer demand is due soon.'
        WHEN REVENUE_SCORE >= SHIPMENT_SCORE
         AND REVENUE_SCORE >= SUPPLIER_SCORE
            THEN 'Customer revenue exposure is high relative to current risk candidates.'
        WHEN SHIPMENT_SCORE >= SUPPLIER_SCORE
            THEN 'An inbound shipment is delayed against its promised date.'
        ELSE 'Historical supplier delivery performance increases exposure.'
    END AS PRIMARY_RISK_REASON,
    REFERENCE_DATE
FROM totaled;

SELECT 'Phase 10 / 24_risk_intelligence.sql complete' AS STATUS;
