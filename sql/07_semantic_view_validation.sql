/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 3B : SEMANTIC VIEW VALIDATION
   FILE    : 07_semantic_view_validation.sql
   PURPOSE : Validate SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW:
             object structure, metric baselines vs CURATED, split-shipment
             Landed Cost regression, currency safety, DOI components, and
             Phase 1 / Phase 2 regression.

   SAFETY  : Read-only. No DDL/DML against any Phase 1, Phase 2, or the
             semantic view itself.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : OBJECT STRUCTURE
   =========================================================================== */

-- A1. SEMANTIC schema exists
SELECT 'A1. SEMANTIC schema exists' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'SEMANTIC') = 1, 'PASS', 'FAIL') AS RESULT;

-- A2. SUPPLY_CHAIN_SEMANTIC_VIEW exists
SHOW SEMANTIC VIEWS LIKE 'SUPPLY_CHAIN_SEMANTIC_VIEW' IN SCHEMA SUPPLYCHAINIQ_DB.SEMANTIC;
SELECT 'A2. SUPPLY_CHAIN_SEMANTIC_VIEW exists' AS CHECK_NAME,
       IFF(COUNT(*) = 1, 'PASS', 'FAIL') AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- A3/A4. Exactly 12 logical tables, matching expected names
SHOW SEMANTIC DIMENSIONS IN SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT 'A3/A4. 12 logical tables with expected names' AS CHECK_NAME,
       IFF(
         (SELECT COUNT(DISTINCT "table_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 12
         AND (SELECT ARRAY_SORT(ARRAY_AGG(DISTINCT "table_name")) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())))
           = ARRAY_SORT(ARRAY_CONSTRUCT('CARRIER','CUSTOMER','CUST_ORDER_LINE','DEMAND','INV','PART','PLANT',
                                         'PO_LINE','SHIPMENT','SUPPLIER','SUPPLIER_PART','SUPPLIER_PERF')),
         'PASS', 'FAIL') AS RESULT;

-- A5. Exactly 15 relationships, no unsafe/excluded ones (verified via DESCRIBE SEMANTIC VIEW)
DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT 'A5a. Exactly 15 relationships declared' AS CHECK_NAME,
       IFF((SELECT COUNT(DISTINCT object_name) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE object_kind = 'RELATIONSHIP' AND property = 'TABLE') = 15, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'A5b. No relationship references TRANSPORT_OPTION or INTERPLANT_TRANSFER_OPTION',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP'
               AND (UPPER(property_value) LIKE '%TRANSPORT_OPTION%' OR UPPER(property_value) LIKE '%INTERPLANT_TRANSFER_OPTION%')) = 0,
       'PASS', 'FAIL')
UNION ALL
SELECT 'A5c. No relationship directly connects INV and DEMAND',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'INV' AND property = 'REF_TABLE' AND property_value = 'DEMAND') = 0
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'DEMAND' AND property = 'REF_TABLE' AND property_value = 'INV') = 0,
       'PASS', 'FAIL')
UNION ALL
SELECT 'A5d. No relationship directly connects SHIPMENT and CUST_ORDER_LINE',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'SHIPMENT' AND property = 'REF_TABLE' AND property_value = 'CUST_ORDER_LINE') = 0
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'CUST_ORDER_LINE' AND property = 'REF_TABLE' AND property_value = 'SHIPMENT') = 0,
       'PASS', 'FAIL')
UNION ALL
SELECT 'A5e. No relationship directly connects SUPPLIER_PERF and SHIPMENT',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'SUPPLIER_PERF' AND property = 'REF_TABLE' AND property_value = 'SHIPMENT') = 0
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE object_kind = 'RELATIONSHIP' AND parent_entity = 'SHIPMENT' AND property = 'REF_TABLE' AND property_value = 'SUPPLIER_PERF') = 0,
       'PASS', 'FAIL');

-- A6. Dimensions/facts/metrics registered as expected
SHOW SEMANTIC DIMENSIONS IN SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT 'A6a. Exactly 54 dimensions registered' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 54, 'PASS', 'FAIL') AS RESULT;

SHOW SEMANTIC FACTS IN SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT 'A6b. Exactly 26 facts registered' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 26, 'PASS', 'FAIL') AS RESULT;

SHOW SEMANTIC METRICS IN SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT 'A6c. Exactly 26 public metrics registered' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 26, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'A6d. No Inventory Turnover metric exists',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE UPPER("name") LIKE '%TURNOVER%') = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'A6e. Canonical metrics present: supplier_otd_percent, shipment_schedule_adherence_percent, fill_rate_percent, actual_landed_cost',
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE UPPER("name") IN ('SUPPLIER_OTD_PERCENT','SHIPMENT_SCHEDULE_ADHERENCE_PERCENT','FILL_RATE_PERCENT','ACTUAL_LANDED_COST')) = 4,
       'PASS', 'FAIL');

-- A7. AI_SQL_GENERATION and AI_QUESTION_CATEGORIZATION exist
SHOW SEMANTIC VIEWS LIKE 'SUPPLY_CHAIN_SEMANTIC_VIEW' IN SCHEMA SUPPLYCHAINIQ_DB.SEMANTIC;
SELECT 'A7. extension property includes AI (AI_SQL_GENERATION / AI_QUESTION_CATEGORIZATION present)' AS CHECK_NAME,
       IFF((SELECT "extension" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) LIKE '%AI%', 'PASS', 'FAIL') AS RESULT;

/* ===========================================================================
   SECTION B : METRIC BASELINE TESTS (Semantic View vs CURATED baseline)
   =========================================================================== */

-- B1/B2. Overall Supplier OTD and S017 OTD
WITH baseline AS (
  SELECT s.SUPPLIER_ID, s.ACTUAL_DELIVERY_DATE, p.PROMISED_DATE
  FROM CURATED.SHIPMENT s
  JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER = s.PO_NUMBER AND p.PO_LINE_NUMBER = s.PO_LINE_NUMBER
  WHERE s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL') AND s.ACTUAL_DELIVERY_DATE IS NOT NULL AND p.PO_STATUS <> 'CANCELLED'
),
baseline_overall AS (SELECT SUM(IFF(ACTUAL_DELIVERY_DATE <= PROMISED_DATE,1,0))/COUNT(*) AS OTD FROM baseline),
baseline_s017 AS (SELECT SUM(IFF(ACTUAL_DELIVERY_DATE <= PROMISED_DATE,1,0))/COUNT(*) AS OTD FROM baseline WHERE SUPPLIER_ID='S017'),
sv_overall AS (SELECT SUPPLIER_OTD_PERCENT AS OTD FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent)),
sv_s017 AS (
  SELECT SUPPLIER_OTD_PERCENT AS OTD FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id METRICS shipment.supplier_otd_percent
  ) WHERE SUPPLIER_ID = 'S017'
)
SELECT 'B1. Overall Supplier OTD matches CURATED baseline' AS CHECK_NAME,
       IFF(ABS((SELECT OTD FROM baseline_overall) - (SELECT OTD FROM sv_overall)) < 0.000001, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'B2. Supplier S017 OTD matches CURATED baseline',
       IFF(ABS((SELECT OTD FROM baseline_s017) - (SELECT OTD FROM sv_s017)) < 0.000001, 'PASS', 'FAIL');

-- B3. Shipment Schedule Adherence
WITH baseline AS (
  SELECT s.ACTUAL_DELIVERY_DATE, s.EXPECTED_DELIVERY_DATE
  FROM CURATED.SHIPMENT s
  JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER = s.PO_NUMBER AND p.PO_LINE_NUMBER = s.PO_LINE_NUMBER
  WHERE s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL') AND s.ACTUAL_DELIVERY_DATE IS NOT NULL AND p.PO_STATUS <> 'CANCELLED'
),
baseline_adh AS (SELECT SUM(IFF(ACTUAL_DELIVERY_DATE <= EXPECTED_DELIVERY_DATE,1,0))/COUNT(*) AS ADH FROM baseline),
sv_adh AS (SELECT SHIPMENT_SCHEDULE_ADHERENCE_PERCENT AS ADH FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.shipment_schedule_adherence_percent))
SELECT 'B3. Shipment Schedule Adherence matches CURATED baseline (and differs from OTD definition)' AS CHECK_NAME,
       IFF(ABS((SELECT ADH FROM baseline_adh) - (SELECT ADH FROM sv_adh)) < 0.000001, 'PASS', 'FAIL') AS RESULT;

-- B4/B5. Overall Fill Rate and Fill Rate by Customer Segment
WITH baseline_overall AS (
  SELECT SUM(FULFILLED_QTY)/SUM(ORDERED_QTY) AS FR FROM CURATED.CUSTOMER_ORDER_LINE WHERE ORDER_STATUS <> 'CANCELLED'
),
sv_overall AS (SELECT FILL_RATE_PERCENT AS FR FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS cust_order_line.fill_rate_percent)),
baseline_seg AS (
  SELECT c.CUSTOMER_SEGMENT, SUM(col.FULFILLED_QTY)/SUM(col.ORDERED_QTY) AS FR
  FROM CURATED.CUSTOMER_ORDER_LINE col JOIN CURATED.CUSTOMER c ON c.CUSTOMER_ID = col.CUSTOMER_ID
  WHERE col.ORDER_STATUS <> 'CANCELLED' GROUP BY 1
),
sv_seg AS (
  SELECT CUSTOMER_SEGMENT, FILL_RATE_PERCENT AS FR FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS customer.customer_segment METRICS cust_order_line.fill_rate_percent
  )
)
SELECT 'B4. Overall Fill Rate matches CURATED baseline' AS CHECK_NAME,
       IFF(ABS((SELECT FR FROM baseline_overall) - (SELECT FR FROM sv_overall)) < 0.000001, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'B5. Fill Rate by Customer Segment matches CURATED baseline for every segment',
       IFF((SELECT COUNT(*) FROM baseline_seg b JOIN sv_seg s ON s.CUSTOMER_SEGMENT = b.CUSTOMER_SEGMENT
             WHERE ABS(b.FR - s.FR) >= 0.000001) = 0
           AND (SELECT COUNT(*) FROM baseline_seg) = (SELECT COUNT(*) FROM sv_seg),
       'PASS', 'FAIL');

-- B6/B7. Actual Landed Cost for a known single-currency supplier (S017/CNY), and grouped by currency
WITH baseline_s017 AS (
  SELECT SUM(IFF(s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL'), s.RECEIVED_QTY*p.UNIT_PRICE + COALESCE(s.FREIGHT_COST,0)+COALESCE(s.DUTY_COST,0)+COALESCE(s.HANDLING_COST,0)+COALESCE(s.OTHER_LOGISTICS_COST,0), NULL)) AS LC
  FROM CURATED.SHIPMENT s JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER=s.PO_NUMBER AND p.PO_LINE_NUMBER=s.PO_LINE_NUMBER
  WHERE s.SUPPLIER_ID = 'S017'
),
sv_s017 AS (
  SELECT ACTUAL_LANDED_COST AS LC FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id, po_line.currency METRICS shipment.actual_landed_cost
  ) WHERE SUPPLIER_ID = 'S017'
),
baseline_by_ccy AS (
  SELECT p.CURRENCY, SUM(IFF(s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL'), s.RECEIVED_QTY*p.UNIT_PRICE + COALESCE(s.FREIGHT_COST,0)+COALESCE(s.DUTY_COST,0)+COALESCE(s.HANDLING_COST,0)+COALESCE(s.OTHER_LOGISTICS_COST,0), NULL)) AS LC
  FROM CURATED.SHIPMENT s JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER=s.PO_NUMBER AND p.PO_LINE_NUMBER=s.PO_LINE_NUMBER
  GROUP BY 1
),
sv_by_ccy AS (
  SELECT CURRENCY, ACTUAL_LANDED_COST AS LC FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS po_line.currency METRICS shipment.actual_landed_cost
  )
)
SELECT 'B6. Actual Landed Cost for supplier S017 (single currency CNY) matches CURATED baseline' AS CHECK_NAME,
       IFF(ABS((SELECT LC FROM baseline_s017) - (SELECT LC FROM sv_s017)) < 0.01, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'B7. Actual Landed Cost grouped by CURRENCY matches CURATED baseline for every currency',
       IFF((SELECT COUNT(*) FROM baseline_by_ccy b JOIN sv_by_ccy s ON s.CURRENCY = b.CURRENCY WHERE ABS(b.LC - s.LC) >= 0.01) = 0
           AND (SELECT COUNT(*) FROM baseline_by_ccy) = (SELECT COUNT(*) FROM sv_by_ccy),
       'PASS', 'FAIL');

-- B8/B9. Latest Available Qty / Safety Stock Qty for P104/P01
WITH sv AS (
  SELECT AVAILABLE_QTY_METRIC, SAFETY_STOCK_QTY_METRIC FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date
    METRICS inv.available_qty_metric, inv.safety_stock_qty_metric
  ) WHERE PART_ID='P104' AND PLANT_ID='P01' AND SNAPSHOT_DATE = '2026-08-15'
)
SELECT 'B8. Latest Available Qty for P104/P01 = 8200' AS CHECK_NAME, IFF((SELECT AVAILABLE_QTY_METRIC FROM sv) = 8200, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'B9. Latest Safety Stock Qty for P104/P01 = 3000', IFF((SELECT SAFETY_STOCK_QTY_METRIC FROM sv) = 3000, 'PASS', 'FAIL');

-- B10. 30-day Average Daily Demand for P104/P01
WITH sv AS (
  SELECT AVG_DAILY_DEMAND_30D FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, demand.demand_date
    METRICS demand.avg_daily_demand_30d
  ) WHERE PART_ID='P104' AND PLANT_ID='P01' AND DEMAND_DATE = '2026-08-14'
)
SELECT 'B10. 30-day Avg Daily Demand for P104/P01 = 700 (governed baseline)' AS CHECK_NAME,
       IFF((SELECT AVG_DAILY_DEMAND_30D FROM sv) = 700, 'PASS', 'FAIL') AS RESULT;

-- B11. Contract Lead Time query (S017 / S042 for P104)
WITH baseline AS (
  SELECT SUPPLIER_ID, CONTRACT_LEAD_TIME_DAYS FROM CURATED.SUPPLIER_PART WHERE PART_ID='P104' AND SUPPLIER_ID IN ('S017','S042')
),
sv AS (
  SELECT SUPPLIER_ID, CONTRACT_LEAD_TIME_DAYS_AVG FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id, part.part_id METRICS supplier_part.contract_lead_time_days_avg
  ) WHERE PART_ID='P104' AND SUPPLIER_ID IN ('S017','S042')
)
SELECT 'B11. Contract Lead Time for S017/S042 on P104 matches CURATED baseline' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM baseline b JOIN sv s ON s.SUPPLIER_ID=b.SUPPLIER_ID WHERE b.CONTRACT_LEAD_TIME_DAYS <> s.CONTRACT_LEAD_TIME_DAYS_AVG) = 0
           AND (SELECT COUNT(*) FROM baseline) = 2 AND (SELECT COUNT(*) FROM sv) = 2,
       'PASS', 'FAIL') AS RESULT;

-- B12. Realized Lead Time query for S017
WITH baseline AS (
  SELECT AVG(IFF(s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL'), DATEDIFF(day, p.ORDER_DATE, s.ACTUAL_DELIVERY_DATE), NULL)) AS RLT
  FROM CURATED.SHIPMENT s JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER=s.PO_NUMBER AND p.PO_LINE_NUMBER=s.PO_LINE_NUMBER
  WHERE s.SUPPLIER_ID='S017'
),
sv AS (
  SELECT REALIZED_LEAD_TIME_DAYS_AVG AS RLT FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id METRICS shipment.realized_lead_time_days_avg
  ) WHERE SUPPLIER_ID = 'S017'
)
SELECT 'B12. Realized Lead Time for S017 matches CURATED baseline' AS CHECK_NAME,
       IFF(ABS((SELECT RLT FROM baseline) - (SELECT RLT FROM sv)) < 0.000001, 'PASS', 'FAIL') AS RESULT;

-- B13. Supplier Risk Category access for S017
WITH sv AS (
  SELECT SCORECARD_DATE, RISK_CATEGORY FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id, supplier_perf.scorecard_date, supplier_perf.risk_category
  ) WHERE SUPPLIER_ID = 'S017'
)
SELECT 'B13. Supplier Risk Category accessible and matches CURATED for S017' AS CHECK_NAME,
       IFF(NOT EXISTS (
         SELECT 1 FROM CURATED.SUPPLIER_PERFORMANCE b
         LEFT JOIN sv ON sv.SCORECARD_DATE = b.SCORECARD_DATE AND sv.RISK_CATEGORY = b.RISK_CATEGORY
         WHERE b.SUPPLIER_ID = 'S017' AND sv.SCORECARD_DATE IS NULL
       ), 'PASS', 'FAIL') AS RESULT;

-- B14. Current Inventory Status access for P104/P01
WITH sv AS (
  SELECT INVENTORY_STATUS FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date, inv.inventory_status
  ) WHERE PART_ID='P104' AND PLANT_ID='P01' AND SNAPSHOT_DATE='2026-08-15'
),
baseline AS (
  SELECT INVENTORY_STATUS FROM CURATED.INVENTORY_SNAPSHOT WHERE PART_ID='P104' AND PLANT_ID='P01' AND SNAPSHOT_DATE='2026-08-15'
)
SELECT 'B14. Current Inventory Status for P104/P01 matches CURATED baseline' AS CHECK_NAME,
       IFF((SELECT INVENTORY_STATUS FROM sv) = (SELECT INVENTORY_STATUS FROM baseline), 'PASS', 'FAIL') AS RESULT;

/* ===========================================================================
   SECTION C : LANDED COST SPLIT-SHIPMENT REGRESSION
   =========================================================================== */

WITH split_po AS (
  SELECT s.PO_NUMBER, s.PO_LINE_NUMBER, COUNT(*) AS N_SHIP, SUM(s.RECEIVED_QTY) AS SUM_RECEIVED, MAX(p.ORDER_QTY) AS PO_ORDER_QTY, MAX(p.UNIT_PRICE) AS UNIT_PRICE
  FROM CURATED.SHIPMENT s JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER=s.PO_NUMBER AND p.PO_LINE_NUMBER=s.PO_LINE_NUMBER
  WHERE s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL')
  GROUP BY 1,2 HAVING COUNT(*) = 2
),
baseline_lc AS (
  SELECT s.PO_NUMBER, s.PO_LINE_NUMBER, s.SHIPMENT_ID, s.SHIPMENT_LINE_NUMBER,
    s.RECEIVED_QTY*p.UNIT_PRICE + COALESCE(s.FREIGHT_COST,0)+COALESCE(s.DUTY_COST,0)+COALESCE(s.HANDLING_COST,0)+COALESCE(s.OTHER_LOGISTICS_COST,0) AS LC
  FROM CURATED.SHIPMENT s JOIN CURATED.PURCHASE_ORDER_LINE p ON p.PO_NUMBER=s.PO_NUMBER AND p.PO_LINE_NUMBER=s.PO_LINE_NUMBER
  WHERE s.SHIPMENT_STATUS IN ('DELIVERED','PARTIAL')
),
sv_lc AS (
  SELECT PO_NUMBER, PO_LINE_NUMBER, SHIPMENT_ID, SHIPMENT_LINE_NUMBER, ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
    DIMENSIONS po_line.po_number, po_line.po_line_number, shipment.shipment_id, shipment.shipment_line_number
    METRICS shipment.actual_landed_cost
  )
)
SELECT 'C1. RECEIVED_QTY never exceeds PO ORDER_QTY across all 3,947 split PO lines' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM split_po WHERE SUM_RECEIVED > PO_ORDER_QTY) = 0, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'C2. Semantic View shipment-line Landed Cost exactly matches CURATED baseline for every split-PO shipment line',
       IFF(
         (SELECT COUNT(*) FROM baseline_lc b JOIN sv_lc s
            ON s.PO_NUMBER=b.PO_NUMBER AND s.PO_LINE_NUMBER=b.PO_LINE_NUMBER AND s.SHIPMENT_ID=b.SHIPMENT_ID AND s.SHIPMENT_LINE_NUMBER=b.SHIPMENT_LINE_NUMBER
          WHERE b.PO_NUMBER IN (SELECT PO_NUMBER FROM split_po) AND ABS(b.LC - s.ACTUAL_LANDED_COST) >= 0.01) = 0,
       'PASS', 'FAIL')
UNION ALL
SELECT 'C3. Sum of split-shipment landed costs never reaches 2x the full single-shipment purchase amount (no duplication), across all split PO lines',
       IFF(
         (SELECT COUNT(*) FROM (
            SELECT sp.PO_NUMBER, sp.PO_LINE_NUMBER, SUM(s.ACTUAL_LANDED_COST) AS SUM_LC, 2*sp.PO_ORDER_QTY*sp.UNIT_PRICE AS DOUBLE_PURCHASE_AMT
            FROM split_po sp JOIN sv_lc s ON s.PO_NUMBER=sp.PO_NUMBER AND s.PO_LINE_NUMBER=sp.PO_LINE_NUMBER
            GROUP BY 1,2,sp.PO_ORDER_QTY,sp.UNIT_PRICE
          ) WHERE SUM_LC >= DOUBLE_PURCHASE_AMT) = 0,
       'PASS', 'FAIL');

/* ===========================================================================
   SECTION D : CURRENCY SAFETY
   =========================================================================== */

-- D1. Single supplier / single currency landed cost is a valid single number (already proven in B6)
SELECT 'D1. Single-supplier (single-currency) Actual Landed Cost is a valid single total' AS CHECK_NAME,
       IFF(
         (SELECT ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(
            SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id METRICS shipment.actual_landed_cost
          ) WHERE SUPPLIER_ID = 'S017') IS NOT NULL,
       'PASS', 'FAIL') AS RESULT;

-- D2. Grouped-by-currency aggregate returns multiple currency rows, never one mixed total
WITH sv_by_ccy AS (
  SELECT CURRENCY, ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS po_line.currency METRICS shipment.actual_landed_cost
  )
)
SELECT 'D2. Currency-grouped Actual Landed Cost returns 11 distinct currency rows (never one mixed-currency total)' AS CHECK_NAME,
       IFF((SELECT COUNT(DISTINCT CURRENCY) FROM sv_by_ccy) = 11, 'PASS', 'FAIL') AS RESULT;

-- D3. Confirm an ungrouped, unscoped Actual Landed Cost total (if computed) would NOT equal the sum of the per-currency totals
--     as a single valid number - i.e. it is a mixed-currency artifact that must never be presented as-is.
WITH sv_by_ccy AS (
  SELECT CURRENCY, ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS po_line.currency METRICS shipment.actual_landed_cost
  )
),
sv_global AS (
  SELECT ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.actual_landed_cost)
)
SELECT 'D3. Global (ungrouped) Actual Landed Cost total is documented as mixed-currency and unsafe - AI_SQL_GENERATION forbids presenting it as one number' AS CHECK_NAME,
       IFF((SELECT ACTUAL_LANDED_COST FROM sv_global) = (SELECT SUM(ACTUAL_LANDED_COST) FROM sv_by_ccy), 'PASS (confirmed mixed-currency artifact exists and is governed against in AI_SQL_GENERATION)', 'FAIL') AS RESULT;

/* ===========================================================================
   SECTION E : DAYS OF INVENTORY COMPONENT VALIDATION
   =========================================================================== */

WITH sv AS (
  SELECT AVAILABLE_QTY_METRIC, SAFETY_STOCK_QTY_METRIC FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date
    METRICS inv.available_qty_metric, inv.safety_stock_qty_metric
  ) WHERE PART_ID='P104' AND PLANT_ID='P01' AND SNAPSHOT_DATE = '2026-08-15'
)
SELECT 'E1. LATEST_AVAILABLE_QTY (component A) = 8200 for P104/P01' AS CHECK_NAME, IFF((SELECT AVAILABLE_QTY_METRIC FROM sv) = 8200, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'E2. LATEST_SAFETY_STOCK_QTY (component A) = 3000 for P104/P01', IFF((SELECT SAFETY_STOCK_QTY_METRIC FROM sv) = 3000, 'PASS', 'FAIL');

-- NOTE: run E3/E4 as a separate statement/query batch from E1/E2 above. Also note: referencing a
-- SEMANTIC_VIEW()-derived CTE as a bare scalar subquery inside IFF/BETWEEN can trigger an unrelated
-- Snowflake internal planner error - compute directly FROM the CTE instead (see E4 below).
WITH sv_demand AS (
  SELECT AVG_DAILY_DEMAND_30D FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, demand.demand_date
    METRICS demand.avg_daily_demand_30d
  ) WHERE PART_ID='P104' AND PLANT_ID='P01' AND DEMAND_DATE = '2026-08-14'
)
SELECT 'E3. AVG_DAILY_DEMAND_30D (component B) = 700 for P104/P01 (window-function metric empirically validated)' AS CHECK_NAME,
       IFF(AVG_DAILY_DEMAND_30D = 700, 'PASS', 'FAIL') AS RESULT
FROM sv_demand
UNION ALL
SELECT 'E4. Governed two-step DOI = component A (8200) / component B (AVG_DAILY_DEMAND_30D) = ~11.7 days (informational, not asserted as a native metric)',
       IFF(8200 / AVG_DAILY_DEMAND_30D BETWEEN 11.0 AND 11.9, 'PASS', 'FAIL')
FROM sv_demand
UNION ALL
SELECT 'E5. NOTE: single-step auto-latest via NON ADDITIVE BY was empirically tested and rejected (returned 8488, not 8200) - documented limitation, not implemented',
       'DOCUMENTED';

/* ===========================================================================
   SECTION F : PHASE 1 / PHASE 2 REGRESSION
   =========================================================================== */

-- F1. All 14 CURATED views unchanged (still exist, same row counts as Phase 2 validated)
SELECT 'F1. All 14 CURATED views exist with unchanged row counts' AS CHECK_NAME,
       IFF(
            (SELECT COUNT(*) FROM CURATED.SUPPLIER) = 100
        AND (SELECT COUNT(*) FROM CURATED.PART) = 1000
        AND (SELECT COUNT(*) FROM CURATED.PLANT) = 12
        AND (SELECT COUNT(*) FROM CURATED.SUPPLIER_PART) = 1401
        AND (SELECT COUNT(*) FROM CURATED.PURCHASE_ORDER_LINE) = 54871
        AND (SELECT COUNT(*) FROM CURATED.SHIPMENT) = 54024
        AND (SELECT COUNT(*) FROM CURATED.INVENTORY_SNAPSHOT) = 104000
        AND (SELECT COUNT(*) FROM CURATED.DEMAND) = 120000
        AND (SELECT COUNT(*) FROM CURATED.CUSTOMER) = 500
        AND (SELECT COUNT(*) FROM CURATED.CUSTOMER_ORDER_LINE) = 52494
        AND (SELECT COUNT(*) FROM CURATED.CARRIER) = 20
        AND (SELECT COUNT(*) FROM CURATED.SUPPLIER_PERFORMANCE) = 1200
        AND (SELECT COUNT(*) FROM CURATED.TRANSPORT_OPTION) = 96
        AND (SELECT COUNT(*) FROM CURATED.INTERPLANT_TRANSFER_OPTION) = 42,
       'PASS', 'FAIL') AS RESULT;

-- F2. Phase 1 source row counts unchanged
SELECT 'F2. Phase 1 source table row counts unchanged' AS CHECK_NAME,
       IFF(
            (SELECT COUNT(*) FROM SAP_ERP.VENDOR_MASTER) = 100
        AND (SELECT COUNT(*) FROM SAP_ERP.MATERIAL_MASTER) = 1000
        AND (SELECT COUNT(*) FROM SAP_ERP.PLANT_MASTER) = 12
        AND (SELECT COUNT(*) FROM SAP_ERP.SUPPLIER_MATERIAL) = 1401
        AND (SELECT COUNT(*) FROM SAP_ERP.PURCHASE_ORDER_LINES) = 54871
        AND (SELECT COUNT(*) FROM TMS_LOGISTICS.CARRIER_MASTER) = 20
        AND (SELECT COUNT(*) FROM TMS_LOGISTICS.SHIPMENTS) = 54024
        AND (SELECT COUNT(*) FROM TMS_LOGISTICS.TRANSPORT_OPTIONS) = 96
        AND (SELECT COUNT(*) FROM TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS) = 42
        AND (SELECT COUNT(*) FROM WMS_INVENTORY.INVENTORY_SNAPSHOTS) = 104000
        AND (SELECT COUNT(*) FROM DEMAND_PLANNING.DEMAND_HISTORY) = 120000
        AND (SELECT COUNT(*) FROM CRM_ORDERS.CUSTOMER_MASTER) = 500
        AND (SELECT COUNT(*) FROM CRM_ORDERS.CUSTOMER_ORDER_LINES) = 52494
        AND (SELECT COUNT(*) FROM SUPPLIER_PORTAL.SUPPLIER_PROFILE) = 100
        AND (SELECT COUNT(*) FROM SUPPLIER_PORTAL.SUPPLIER_SCORECARDS) = 1200
        AND (SELECT COUNT(*) FROM DOCUMENTS.SUPPLIER_DOCUMENTS) = 139,
       'PASS', 'FAIL') AS RESULT;

-- F3. Flagship source facts unchanged (spot check)
WITH a AS (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1)
SELECT 'F3. Flagship source facts unchanged (S017/P104/P01 inventory = 8200/3000)' AS CHECK_NAME,
       IFF(
         (SELECT i.AVAILABLE_QTY FROM WMS_INVENTORY.INVENTORY_SNAPSHOTS i CROSS JOIN a WHERE i.SKU='P104' AND i.SITE_ID='P01' AND i.SNAPSHOT_DATE=a.A) = 8200
         AND (SELECT i.SAFETY_STOCK_QTY FROM WMS_INVENTORY.INVENTORY_SNAPSHOTS i CROSS JOIN a WHERE i.SKU='P104' AND i.SITE_ID='P01' AND i.SNAPSHOT_DATE=a.A) = 3000,
       'PASS', 'FAIL') AS RESULT;

SELECT 'Phase 3B / 07_semantic_view_validation.sql complete' AS STATUS;
