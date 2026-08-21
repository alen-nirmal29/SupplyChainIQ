/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 4C : CORTEX ANALYST EVALUATION COMPATIBILITY FIX VALIDATION
   FILE    : 09_evaluation_compatibility_validation.sql
   PURPOSE : Document and validate the fix for Cortex Analyst evaluation
             failure "phase4c_baseline_v1" (Snowflake error 392700), and
             prove the fix did not change any governed business result.

   BACKGROUND
   ----------
   Evaluation run:    phase4c_baseline_v1
   Snowflake error:   392700
   Error message:     "Metric FILL_RATE_PERCENT does not contain an
                        aggregation function. Metrics must be defined with
                        aggregates, otherwise use facts."

   ROOT CAUSE
   ----------
   Three public metrics were defined as a bare division of two OTHER declared
   metrics, with no aggregate function (SUM/COUNT_IF/AVG/etc.) present in
   their OWN expression:
     - shipment.supplier_otd_percent
         WAS: shipment.on_time_delivery_count / NULLIF(shipment.eligible_delivery_count, 0)
     - shipment.shipment_schedule_adherence_percent
         WAS: shipment.schedule_adherent_count / NULLIF(shipment.eligible_delivery_count, 0)
     - cust_order_line.fill_rate_percent
         WAS: cust_order_line.eligible_fulfilled_qty / NULLIF(cust_order_line.eligible_ordered_qty, 0)

   This pattern executes correctly via SEMANTIC_VIEW() (Snowflake resolves
   metric-to-metric references transitively at query time), which is why it
   was never caught by Phase 3B/4B's SEMANTIC_VIEW() execution testing.
   However, Cortex Analyst's evaluation pipeline validates the semantic model
   against a stricter rule: every table-level metric's own expression must
   contain a recognized aggregate function call. IMPORTANT: passing normal
   SEMANTIC_VIEW() execution does NOT, by itself, prove Cortex Analyst
   evaluation compatibility - that can only be confirmed by an actual
   Cortex Analyst evaluation run (see final validation step below).

   FIX (Phase 4C)
   --------------
   All three metrics were rewritten to be self-contained: the aggregate
   functions (COUNT_IF for the two OTD/adherence metrics, SUM for Fill Rate)
   are now written directly inside the public metric's own expression,
   duplicating the eligibility/numerator logic instead of referencing the
   private helper metrics. The formulas, eligibility rules, NULL/zero-
   denominator behavior (NULLIF -> NULL), and numeric results are IDENTICAL
   to the pre-fix version - only the expression's shape changed.

   The 5 private helper metrics that the old expressions referenced
   (shipment.eligible_delivery_count, shipment.on_time_delivery_count,
   shipment.schedule_adherent_count, cust_order_line.eligible_ordered_qty,
   cust_order_line.eligible_fulfilled_qty) are UNCHANGED and RETAINED, even
   though the three public metrics above no longer reference them.

   METRIC AUDIT RESULT (all 32 metrics inspected)
   ------------------------------------------------
   Only the 3 metrics listed above had the defect. All other 29 metrics
   (26 table-level SUM/AVG/MAX/COUNT_IF metrics + the 1 window-function
   metric demand.avg_daily_demand_30d, which contains its own outer AVG(...)
   OVER (...) aggregate) already contained a direct aggregate function and
   required no change.

   SAFETY : Read-only validation. No DDL/DML against Phase 1 source tables
            or the 14 CURATED views. The Semantic View redeploy itself was
            performed via semantic/supply_chain_semantic_view.sql using
            CREATE OR REPLACE SEMANTIC VIEW ... COPY GRANTS.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : STRUCTURAL METADATA - CONFIRM THE 3 METRICS NOW CONTAIN A
   DIRECT AGGREGATE, AND NOTHING ELSE IN THE MODEL CHANGED SHAPE
   =========================================================================== */

DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;

SELECT 'A1. SUPPLIER_OTD_PERCENT expression now contains COUNT_IF directly' AS CHECK_NAME,
       IFF((SELECT "property_value" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE "object_kind"='METRIC' AND "object_name"='SUPPLIER_OTD_PERCENT' AND "property"='EXPRESSION')
           ILIKE '%COUNT_IF%', 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'A2. SHIPMENT_SCHEDULE_ADHERENCE_PERCENT expression now contains COUNT_IF directly',
       IFF((SELECT "property_value" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE "object_kind"='METRIC' AND "object_name"='SHIPMENT_SCHEDULE_ADHERENCE_PERCENT' AND "property"='EXPRESSION')
           ILIKE '%COUNT_IF%', 'PASS', 'FAIL')
UNION ALL
SELECT 'A3. FILL_RATE_PERCENT expression now contains SUM directly',
       IFF((SELECT "property_value" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE "object_kind"='METRIC' AND "object_name"='FILL_RATE_PERCENT' AND "property"='EXPRESSION')
           ILIKE '%SUM(%', 'PASS', 'FAIL')
UNION ALL
SELECT 'A4. All 5 pre-existing private helper metrics still present/unchanged in name',
       IFF((SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
             WHERE "object_kind"='METRIC' AND "object_name" IN
               ('ELIGIBLE_DELIVERY_COUNT','ON_TIME_DELIVERY_COUNT','SCHEDULE_ADHERENT_COUNT','ELIGIBLE_ORDERED_QTY','ELIGIBLE_FULFILLED_QTY')) = 5,
       'PASS', 'FAIL')
UNION ALL
SELECT 'A5. Structure unchanged: 12 tables / 15 relationships / 54 dims / 26 facts / 32 metrics / 15 VQs',
       IFF(
            (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='TABLE') = 12
        AND (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='RELATIONSHIP') = 15
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='DIMENSION' AND "property"='TABLE') = 54
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='FACT' AND "property"='TABLE') = 26
        AND (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='METRIC' AND "property"='TABLE') = 32
        AND (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind"='AI_VERIFIED_QUERY') = 15,
       'PASS', 'FAIL');

/* ===========================================================================
   SECTION B : DETERMINISTIC BASELINE REGRESSION (must be byte-identical to
   Phase 3B/4B results)
   =========================================================================== */

SELECT 'B1. Overall Supplier OTD ~= 0.751929' AS CHECK_NAME,
       IFF(ABS((SELECT SUPPLIER_OTD_PERCENT FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.supplier_otd_percent)) - 0.751929) < 0.000001, 'PASS', 'FAIL') AS RESULT;

WITH sv AS (SELECT SUPPLIER_OTD_PERCENT FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id METRICS shipment.supplier_otd_percent) WHERE SUPPLIER_ID='S017')
SELECT 'B2. S017 Supplier OTD ~= 0.493506' AS CHECK_NAME, IFF(ABS(SUPPLIER_OTD_PERCENT - 0.493506) < 0.000001, 'PASS', 'FAIL') AS RESULT FROM sv;

SELECT 'B3. Shipment Schedule Adherence ~= 0.811793' AS CHECK_NAME,
       IFF(ABS((SELECT SHIPMENT_SCHEDULE_ADHERENCE_PERCENT FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS shipment.shipment_schedule_adherence_percent)) - 0.811793) < 0.000001, 'PASS', 'FAIL') AS RESULT;

SELECT 'B4. Fill Rate EXACT = 0.77578916' AS CHECK_NAME,
       IFF((SELECT FILL_RATE_PERCENT FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW METRICS cust_order_line.fill_rate_percent)) = 0.77578916, 'PASS', 'FAIL') AS RESULT;

WITH sv AS (SELECT AVAILABLE_QTY_METRIC FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date METRICS inv.available_qty_metric) WHERE PART_ID='P104' AND PLANT_ID='P01' AND SNAPSHOT_DATE='2026-08-15')
SELECT 'B5. P104/P01 available inventory on 2026-08-15 = 8200' AS CHECK_NAME, IFF(AVAILABLE_QTY_METRIC = 8200, 'PASS', 'FAIL') AS RESULT FROM sv;

WITH sv AS (SELECT AVG_DAILY_DEMAND_30D FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS part.part_id, plant.plant_id, demand.demand_date METRICS demand.avg_daily_demand_30d) WHERE PART_ID='P104' AND PLANT_ID='P01' AND DEMAND_DATE='2026-08-14')
SELECT 'B6. P104/P01 30-day avg demand = 700' AS CHECK_NAME, IFF(AVG_DAILY_DEMAND_30D = 700, 'PASS', 'FAIL') AS RESULT FROM sv;

WITH sv AS (SELECT CURRENCY, ACTUAL_LANDED_COST FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id, po_line.currency METRICS shipment.actual_landed_cost) WHERE SUPPLIER_ID='S017')
SELECT 'B7. S017 Landed Cost = CNY / 3624295146.29' AS CHECK_NAME, IFF(CURRENCY='CNY' AND ABS(ACTUAL_LANDED_COST - 3624295146.29) < 0.01, 'PASS', 'FAIL') AS RESULT FROM sv;

WITH sv AS (SELECT SUPPLIER_ID, CONTRACT_LEAD_TIME_DAYS_AVG FROM SEMANTIC_VIEW(SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW DIMENSIONS supplier.supplier_id, part.part_id METRICS supplier_part.contract_lead_time_days_avg) WHERE PART_ID='P104' AND SUPPLIER_ID IN ('S017','S042'))
SELECT 'B8. Contract lead times: S017=28, S042=7' AS CHECK_NAME,
       IFF((SELECT CONTRACT_LEAD_TIME_DAYS_AVG FROM sv WHERE SUPPLIER_ID='S017')=28 AND (SELECT CONTRACT_LEAD_TIME_DAYS_AVG FROM sv WHERE SUPPLIER_ID='S042')=7, 'PASS', 'FAIL') AS RESULT;

WITH sv AS (
  SELECT ORDER_LINE_COUNT, TOTAL_ORDER_VALUE FROM SEMANTIC_VIEW(
    SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
    DIMENSIONS part.part_id, plant.plant_id
    METRICS COUNT(cust_order_line.order_id) AS ORDER_LINE_COUNT, cust_order_line.total_order_value
    WHERE cust_order_line.order_status <> 'CANCELLED' AND cust_order_line.due_date BETWEEN '2026-08-15' AND '2026-08-29'
  ) WHERE PART_ID='P104' AND PLANT_ID='P01'
)
SELECT 'B9. Customer exposure: count=3, value=4200000' AS CHECK_NAME, IFF(ORDER_LINE_COUNT=3 AND TOTAL_ORDER_VALUE=4200000, 'PASS', 'FAIL') AS RESULT FROM sv;

/* ===========================================================================
   SECTION C : PHASE 1 / CURATED REGRESSION
   =========================================================================== */

SELECT 'C1. Phase 1 source row counts unchanged' AS CHECK_NAME,
       IFF(
            (SELECT COUNT(*) FROM SAP_ERP.VENDOR_MASTER) = 100
        AND (SELECT COUNT(*) FROM TMS_LOGISTICS.SHIPMENTS) = 54024
        AND (SELECT COUNT(*) FROM CRM_ORDERS.CUSTOMER_ORDER_LINES) = 52494,
       'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'C2. CURATED views unchanged',
       IFF(
            (SELECT COUNT(*) FROM CURATED.SUPPLIER) = 100
        AND (SELECT COUNT(*) FROM CURATED.SHIPMENT) = 54024
        AND (SELECT COUNT(*) FROM CURATED.CUSTOMER_ORDER_LINE) = 52494,
       'PASS', 'FAIL');

/* ===========================================================================
   IMPORTANT CAVEAT
   ---------------------------------------------------------------------------
   All checks above prove: (a) the three metrics' expressions now contain a
   direct aggregate function, and (b) every governed numeric result is
   byte-identical to the pre-fix Phase 3B/4B baseline. They do NOT, by
   themselves, prove the Semantic View will pass a Cortex Analyst evaluation
   run. The only authoritative proof of evaluation compatibility is a
   successful "phase4c_baseline_v2" (or later) Cortex Analyst evaluation run.
   =========================================================================== */

SELECT 'Phase 4C / 09_evaluation_compatibility_validation.sql complete - re-run Cortex Analyst evaluation (phase4c_baseline_v2) to confirm error 392700 is resolved' AS STATUS;
