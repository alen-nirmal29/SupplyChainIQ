/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 7B : INTERVENTION DECISION TOOLS - AUTHORITATIVE DDL
   FILE    : 15_intervention_decision_tools.sql
   PURPOSE : Create the deterministic, read-only supply-chain intervention
             decision-support layer and attach it as a THIRD custom tool to
             the existing SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT.
             Recommendation-only: no business-action execution in this phase.

   SAFETY  : Creates SUPPLYCHAINIQ_DB.DECISION schema (if absent) and the
             read-only stored procedure EVALUATE_SUPPLY_CHAIN_INTERVENTIONS
             (SELECT-only body, EXECUTE AS CALLER, no INSERT/UPDATE/DELETE/
             MERGE/TRUNCATE/CREATE-operational-record anywhere). Redeploys
             the existing Agent via CREATE OR REPLACE AGENT with the FULL
             preserved Phase 6B specification plus the new tool - existing
             tools (supply_chain_analytics, supplier_document_search),
             instructions, budgets, and Search/Analyst resources are
             reproduced verbatim, only extended, never removed.

   EMPIRICAL INTEGRATION FIXES (discovered via live DATA_AGENT_RUN testing,
   documented rather than silently worked around):
   1. Parameter-name matching: a "generic" custom tool backed by a
      `type: procedure` resource invokes the procedure using NAMED
      arguments that must match the tool's input_schema property names
      exactly (supplier_id, part_id, destination_plant_id). An initial
      version used prefixed parameter names (P_SUPPLIER_ID, P_PART_ID,
      P_DESTINATION_PLANT_ID) and every call failed with "named arguments
      ... do not match any signature". Fixed by renaming the procedure's
      parameters to SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID exactly
      (bind-variable syntax :SUPPLIER_ID etc. remains unambiguous against
      same-named table columns inside the query body).
   2. Single-cell result requirement: the generic/procedure tool calling
      convention expects the procedure to return exactly one row and one
      column ("expected a single cell result set, got 4 rows and 22
      columns"). A RETURNS TABLE(...) procedure returning one row per
      intervention (4 rows) is therefore NOT callable this way. Fixed by
      changing the procedure to RETURNS VARIANT and building the same
      four-row result set as a single JSON array via
      ARRAY_AGG(OBJECT_CONSTRUCT(...)) WITHIN GROUP (...), so the tool
      call returns one cell containing the full array. The procedure
      remains 100% deterministic SQL; only the return-value packaging
      changed, not the underlying calculation.

   GOVERNANCE PATCH (post-Phase-7B clarification, no redesign): the procedure
   may legitimately identify the fastest ACTIVE structured transport/
   replenishment lane (e.g. the flagship Road 3-day option for S017/P104),
   which can differ from the transport mode discussed in a supplier's
   SLA/contract (e.g. DOC000217's approved Air expedite lane). This is NOT a
   defect - the tool computes an "operational recommendation" from
   structured feasibility/quantity/timing/cost data only; contractual
   applicability of a specific mode is a separate evidence layer supplied
   only by supplier_document_search. The procedure's deterministic ranking,
   SQL, and calculations are UNCHANGED by this patch. Only the Agent's
   orchestration instructions (below, Section D) were extended so the Agent
   explicitly separates "operational recommendation" from "contract
   evidence" and never claims a document authorizes a different mode than
   the one it actually discusses. Re-validated via the flagship and hybrid
   SLA tests in 16_intervention_decision_validation.sql.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : DECISION SCHEMA (create only if absent)
   =========================================================================== */
CREATE SCHEMA IF NOT EXISTS SUPPLYCHAINIQ_DB.DECISION
  COMMENT = 'Phase 7: deterministic, read-only supply-chain intervention decision-support layer (expedite / interplant transfer / alternate supplier). No writes to operational tables. Recommendation-only - execution belongs to a later phase.';

USE SCHEMA DECISION;

/* ===========================================================================
   SECTION B : DETERMINISTIC REFERENCE DATE
   Derived from SUPPLYCHAINIQ_DB.PUBLIC.DATASET_METADATA.DATASET_ANCHOR_DATE
   (latest VERSION), NOT CURRENT_DATE. Confirmed value for this dataset:
   2026-08-15. DATASET_METADATA.NOTES explicitly names S017/P104/P01 as this
   dataset's flagship scenario, and 2026-08-15 matches the "latest snapshot"
   date used consistently by inventory/demand throughout Phases 4-6.
   =========================================================================== */

/* ===========================================================================
   SECTION C : READ-ONLY STORED PROCEDURE
   EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID)
   Returns a VARIANT: a JSON array with one object per evaluated intervention:
     - EXPEDITE_CURRENT_SHIPMENT  (always FEASIBLE=false - rerouting an
       in-transit shipment is not supported by any structured data field;
       this entry exists to make that explicit rather than silent)
     - EXPEDITED_REPLENISHMENT    (new order via the fastest ACTIVE transport
       lane for the supplier's region -> destination plant)
     - INTERPLANT_TRANSFER        (one entry per candidate source plant with
       an active lane and inventory; a placeholder FEASIBLE=false entry when
       no candidate exists)
     - ALTERNATE_SUPPLIER         (one entry per approved active alternate
       supplier; a placeholder FEASIBLE=false entry when none exist)
   All monetary fields are null/false-governed unless a genuine absolute,
   currency-labeled cost basis exists in structured data (see
   docs/intervention_decision_design.md Section 6 for the full cost-
   governance rationale). Recommendation ranking (RECOMMENDATION_RANK,
   RECOMMENDED) is computed deterministically by the procedure itself, not
   by the LLM.
   =========================================================================== */

CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(
  SUPPLIER_ID VARCHAR,
  PART_ID VARCHAR,
  DESTINATION_PLANT_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  res VARIANT;
BEGIN
  res := (
    WITH ref AS (
      SELECT DATASET_ANCHOR_DATE AS REFERENCE_DATE FROM SUPPLYCHAINIQ_DB.PUBLIC.DATASET_METADATA ORDER BY VERSION DESC LIMIT 1
    ),
    dest_inv AS (
      SELECT i.AVAILABLE_QTY, i.SAFETY_STOCK_QTY, GREATEST(i.AVAILABLE_QTY - i.SAFETY_STOCK_QTY,0) AS USABLE_QTY, i.SNAPSHOT_DATE
      FROM SUPPLYCHAINIQ_DB.CURATED.INVENTORY_SNAPSHOT i
      WHERE i.PART_ID = :PART_ID AND i.PLANT_ID = :DESTINATION_PLANT_ID
      QUALIFY ROW_NUMBER() OVER (ORDER BY i.SNAPSHOT_DATE DESC) = 1
    ),
    demand_ctx AS (
      SELECT SUM(GREATEST(c.ORDERED_QTY - c.FULFILLED_QTY,0)) AS REQUIRED_QTY, MIN(c.DUE_DATE) AS FIRST_DUE_DATE, SUM(c.ORDER_VALUE) AS EXPOSURE_VALUE
      FROM SUPPLYCHAINIQ_DB.CURATED.CUSTOMER_ORDER_LINE c, ref
      WHERE c.PART_ID = :PART_ID AND c.PLANT_ID = :DESTINATION_PLANT_ID
        AND c.ORDER_STATUS NOT IN ('CANCELLED','FULFILLED')
        AND c.DUE_DATE BETWEEN ref.REFERENCE_DATE AND DATEADD(day,14,ref.REFERENCE_DATE)
    ),
    shortage_ctx AS (
      SELECT ref.REFERENCE_DATE, dest_inv.AVAILABLE_QTY, dest_inv.SAFETY_STOCK_QTY, dest_inv.USABLE_QTY,
             COALESCE(demand_ctx.REQUIRED_QTY,0) AS REQUIRED_QTY, demand_ctx.FIRST_DUE_DATE, demand_ctx.EXPOSURE_VALUE,
             GREATEST(COALESCE(demand_ctx.REQUIRED_QTY,0) - COALESCE(dest_inv.USABLE_QTY,0), 0) AS SHORTAGE_BEFORE
      FROM ref
      LEFT JOIN dest_inv ON TRUE
      LEFT JOIN demand_ctx ON TRUE
    ),
    cur_ship AS (
      SELECT s.SHIPMENT_ID, s.SUPPLIER_ID, s.TRANSPORT_MODE, s.PROJECTED_DELIVERY_DATE, s.SHIPPED_QTY, s.RECEIVED_QTY, p.PROMISED_DATE
      FROM SUPPLYCHAINIQ_DB.CURATED.SHIPMENT s
      JOIN SUPPLYCHAINIQ_DB.CURATED.PURCHASE_ORDER_LINE p ON s.PO_NUMBER=p.PO_NUMBER AND s.PO_LINE_NUMBER=p.PO_LINE_NUMBER
      WHERE s.SUPPLIER_ID = :SUPPLIER_ID AND s.PART_ID = :PART_ID AND s.PLANT_ID = :DESTINATION_PLANT_ID
        AND s.SHIPMENT_STATUS = 'IN_TRANSIT'
      QUALIFY ROW_NUMBER() OVER (ORDER BY s.PROJECTED_DELIVERY_DATE ASC) = 1
    ),
    sup_region AS (SELECT REGION FROM SUPPLYCHAINIQ_DB.CURATED.SUPPLIER WHERE SUPPLIER_ID = :SUPPLIER_ID),
    sup_capacity AS (SELECT MAX_WEEKLY_SUPPLY_QTY, CONTRACT_LEAD_TIME_DAYS, CURRENCY FROM SUPPLYCHAINIQ_DB.CURATED.SUPPLIER_PART WHERE SUPPLIER_ID = :SUPPLIER_ID AND PART_ID = :PART_ID),
    expedite_lane AS (
      SELECT t.TRANSPORT_MODE, t.EXPEDITED_TRANSIT_DAYS, t.EXPEDITE_COST_FACTOR
      FROM SUPPLYCHAINIQ_DB.CURATED.TRANSPORT_OPTION t, sup_region r
      WHERE t.ORIGIN_REGION = r.REGION AND t.DESTINATION_PLANT_ID = :DESTINATION_PLANT_ID
        AND t.ACTIVE_FLAG = TRUE AND t.EXPEDITED_TRANSIT_DAYS IS NOT NULL
      QUALIFY ROW_NUMBER() OVER (ORDER BY t.EXPEDITED_TRANSIT_DAYS ASC) = 1
    ),
    transfer_cand AS (
      SELECT it.ORIGIN_PLANT_ID, it.TRANSPORT_MODE, it.TRANSIT_DAYS, it.COST_PER_UNIT, it.FIXED_TRANSFER_COST, it.MAX_TRANSFER_QTY,
             inv.AVAILABLE_QTY AS SRC_AVAILABLE_QTY, inv.SAFETY_STOCK_QTY AS SRC_SAFETY_STOCK_QTY,
             GREATEST(inv.AVAILABLE_QTY - inv.SAFETY_STOCK_QTY,0) AS SAFE_TRANSFERABLE_QTY
      FROM SUPPLYCHAINIQ_DB.CURATED.INTERPLANT_TRANSFER_OPTION it
      JOIN (
        SELECT PART_ID, PLANT_ID, SNAPSHOT_DATE, AVAILABLE_QTY, SAFETY_STOCK_QTY
        FROM SUPPLYCHAINIQ_DB.CURATED.INVENTORY_SNAPSHOT
        WHERE PART_ID = :PART_ID
        QUALIFY ROW_NUMBER() OVER (PARTITION BY PLANT_ID ORDER BY SNAPSHOT_DATE DESC) = 1
      ) inv ON inv.PLANT_ID = it.ORIGIN_PLANT_ID
      WHERE it.DESTINATION_PLANT_ID = :DESTINATION_PLANT_ID AND it.ACTIVE_FLAG = TRUE AND it.ORIGIN_PLANT_ID <> :DESTINATION_PLANT_ID
    ),
    alt_supplier_cand AS (
      SELECT sp.SUPPLIER_ID, sp.CONTRACT_LEAD_TIME_DAYS, sp.MAX_WEEKLY_SUPPLY_QTY, sp.MINIMUM_ORDER_QTY, sp.AGREED_UNIT_PRICE, sp.CURRENCY,
             s.VENDOR_STATUS, s.VENDOR_TIER
      FROM SUPPLYCHAINIQ_DB.CURATED.SUPPLIER_PART sp
      JOIN SUPPLYCHAINIQ_DB.CURATED.SUPPLIER s ON s.SUPPLIER_ID = sp.SUPPLIER_ID
      , ref
      WHERE sp.PART_ID = :PART_ID AND sp.SUPPLIER_ID <> :SUPPLIER_ID
        AND s.VENDOR_STATUS = 'Active'
        AND sp.VALID_TO >= ref.REFERENCE_DATE
    ),
    row_expedite_current AS (
      SELECT
        'EXPEDITE_CURRENT_SHIPMENT' AS INTERVENTION_TYPE,
        FALSE AS FEASIBLE,
        CASE WHEN cs.SHIPMENT_ID IS NULL THEN 'No IN_TRANSIT shipment found for this supplier/part/destination plant.'
             ELSE 'Shipment ' || cs.SHIPMENT_ID || ' is already IN_TRANSIT via ' || cs.TRANSPORT_MODE || '. No structured data field supports changing the transport mode or route of an in-transit shipment; rerouting an active shipment is not supported by available data.'
        END AS REASON,
        NULL::VARCHAR AS SOURCE_LOCATION,
        :SUPPLIER_ID AS SOURCE_SUPPLIER,
        cs.SHIPPED_QTY AS QUANTITY_AVAILABLE,
        NULL::NUMBER AS QUANTITY_USED,
        sc.SHORTAGE_BEFORE AS SHORTAGE_BEFORE,
        sc.SHORTAGE_BEFORE AS SHORTAGE_AFTER,
        sc.REFERENCE_DATE AS REFERENCE_DATE,
        cs.PROJECTED_DELIVERY_DATE AS ARRIVAL_DATE,
        sc.FIRST_DUE_DATE AS FIRST_CUSTOMER_DUE_DATE,
        CASE WHEN cs.PROJECTED_DELIVERY_DATE IS NULL OR sc.FIRST_DUE_DATE IS NULL THEN NULL ELSE cs.PROJECTED_DELIVERY_DATE <= sc.FIRST_DUE_DATE END AS ARRIVES_IN_TIME,
        DATEDIFF(day, cs.PROMISED_DATE, cs.PROJECTED_DELIVERY_DATE) AS TRANSIT_OR_LEAD_DAYS,
        NULL::NUMBER AS ESTIMATED_COST,
        NULL::VARCHAR AS CURRENCY,
        'Not applicable - rerouting not supported; no cost basis calculated.' AS COST_BASIS,
        FALSE AS COST_COMPARABLE,
        CASE WHEN cs.SHIPMENT_ID IS NOT NULL THEN 'Shipment already ' || DATEDIFF(day, cs.PROMISED_DATE, cs.PROJECTED_DELIVERY_DATE) || ' day(s) delayed versus its promised date.' ELSE NULL END AS RISKS_OR_CONSTRAINTS,
        'CURATED.SHIPMENT, CURATED.PURCHASE_ORDER_LINE' AS EVIDENCE_SOURCE
      FROM shortage_ctx sc
      LEFT JOIN cur_ship cs ON TRUE
    ),
    row_expedited_replenishment AS (
      SELECT
        'EXPEDITED_REPLENISHMENT' AS INTERVENTION_TYPE,
        CASE WHEN el.EXPEDITED_TRANSIT_DAYS IS NOT NULL AND sup.MAX_WEEKLY_SUPPLY_QTY > 0 AND sc.SHORTAGE_BEFORE > 0
                  AND (sc.FIRST_DUE_DATE IS NULL OR DATEADD(day, el.EXPEDITED_TRANSIT_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE)
             THEN TRUE ELSE FALSE END AS FEASIBLE,
        CASE
          WHEN el.EXPEDITED_TRANSIT_DAYS IS NULL THEN 'No active expedited transport lane found from supplier region to destination plant.'
          WHEN sup.MAX_WEEKLY_SUPPLY_QTY IS NULL OR sup.MAX_WEEKLY_SUPPLY_QTY <= 0 THEN 'No supplier weekly-supply capacity available for this part.'
          WHEN sc.SHORTAGE_BEFORE = 0 THEN 'No shortage currently projected; expedited replenishment not required.'
          WHEN sc.FIRST_DUE_DATE IS NOT NULL AND DATEADD(day, el.EXPEDITED_TRANSIT_DAYS, sc.REFERENCE_DATE) > sc.FIRST_DUE_DATE THEN 'Expedited transit would still arrive after the first affected customer due date.'
          ELSE 'Active expedited lane and supplier capacity support a new expedited replenishment order.'
        END AS REASON,
        el.TRANSPORT_MODE AS SOURCE_LOCATION,
        :SUPPLIER_ID AS SOURCE_SUPPLIER,
        sup.MAX_WEEKLY_SUPPLY_QTY AS QUANTITY_AVAILABLE,
        CASE WHEN el.EXPEDITED_TRANSIT_DAYS IS NOT NULL AND sup.MAX_WEEKLY_SUPPLY_QTY > 0 THEN LEAST(sc.SHORTAGE_BEFORE, sup.MAX_WEEKLY_SUPPLY_QTY) ELSE NULL END AS QUANTITY_USED,
        sc.SHORTAGE_BEFORE AS SHORTAGE_BEFORE,
        CASE WHEN el.EXPEDITED_TRANSIT_DAYS IS NOT NULL AND sup.MAX_WEEKLY_SUPPLY_QTY > 0
             THEN GREATEST(sc.SHORTAGE_BEFORE - LEAST(sc.SHORTAGE_BEFORE, sup.MAX_WEEKLY_SUPPLY_QTY), 0)
             ELSE sc.SHORTAGE_BEFORE END AS SHORTAGE_AFTER,
        sc.REFERENCE_DATE AS REFERENCE_DATE,
        CASE WHEN el.EXPEDITED_TRANSIT_DAYS IS NOT NULL THEN DATEADD(day, el.EXPEDITED_TRANSIT_DAYS, sc.REFERENCE_DATE) ELSE NULL END AS ARRIVAL_DATE,
        sc.FIRST_DUE_DATE AS FIRST_CUSTOMER_DUE_DATE,
        CASE WHEN el.EXPEDITED_TRANSIT_DAYS IS NULL OR sc.FIRST_DUE_DATE IS NULL THEN NULL
             ELSE DATEADD(day, el.EXPEDITED_TRANSIT_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE END AS ARRIVES_IN_TIME,
        el.EXPEDITED_TRANSIT_DAYS AS TRANSIT_OR_LEAD_DAYS,
        NULL::NUMBER AS ESTIMATED_COST,
        NULL::VARCHAR AS CURRENCY,
        CASE WHEN el.EXPEDITE_COST_FACTOR IS NOT NULL
             THEN el.EXPEDITE_COST_FACTOR || 'x expedited cost factor available (TRANSPORT_OPTION.EXPEDITE_COST_FACTOR); no governed absolute base freight cost exists in structured data for this lane to compute an absolute currency value.'
             ELSE 'No expedited transport lane/cost factor available.'
        END AS COST_BASIS,
        FALSE AS COST_COMPARABLE,
        'Arrival date reflects transit time only per TRANSPORT_OPTION; supplier production/order-confirmation lead time is not separately added and may extend the actual arrival date. Selected lane is the fastest ACTIVE expedited option in structured data by transit days for the supplier region; cross-check supplier contract/SLA documents separately for any contractually-approved expedite lane.' AS RISKS_OR_CONSTRAINTS,
        'CURATED.TRANSPORT_OPTION, CURATED.SUPPLIER, CURATED.SUPPLIER_PART' AS EVIDENCE_SOURCE
      FROM shortage_ctx sc
      LEFT JOIN expedite_lane el ON TRUE
      LEFT JOIN sup_capacity sup ON TRUE
    ),
    row_transfer AS (
      SELECT
        'INTERPLANT_TRANSFER' AS INTERVENTION_TYPE,
        (tc.SAFE_TRANSFERABLE_QTY > 0 AND tc.MAX_TRANSFER_QTY > 0 AND sc.SHORTAGE_BEFORE > 0
          AND LEAST(sc.SHORTAGE_BEFORE, tc.SAFE_TRANSFERABLE_QTY, tc.MAX_TRANSFER_QTY) > 0
          AND (sc.FIRST_DUE_DATE IS NULL OR DATEADD(day, tc.TRANSIT_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE)
        ) AS FEASIBLE,
        CASE
          WHEN tc.SAFE_TRANSFERABLE_QTY <= 0 THEN 'Source plant ' || tc.ORIGIN_PLANT_ID || ' has no inventory available above its own safety stock.'
          WHEN tc.MAX_TRANSFER_QTY <= 0 THEN 'Lane from ' || tc.ORIGIN_PLANT_ID || ' has no transfer capacity.'
          WHEN sc.FIRST_DUE_DATE IS NOT NULL AND DATEADD(day, tc.TRANSIT_DAYS, sc.REFERENCE_DATE) > sc.FIRST_DUE_DATE THEN 'Transfer from ' || tc.ORIGIN_PLANT_ID || ' would arrive after the first affected customer due date.'
          ELSE 'Source plant ' || tc.ORIGIN_PLANT_ID || ' has sufficient stock above its safety stock and an active transfer lane.'
        END AS REASON,
        tc.ORIGIN_PLANT_ID AS SOURCE_LOCATION,
        NULL::VARCHAR AS SOURCE_SUPPLIER,
        tc.SAFE_TRANSFERABLE_QTY AS QUANTITY_AVAILABLE,
        LEAST(sc.SHORTAGE_BEFORE, tc.SAFE_TRANSFERABLE_QTY, tc.MAX_TRANSFER_QTY) AS QUANTITY_USED,
        sc.SHORTAGE_BEFORE AS SHORTAGE_BEFORE,
        GREATEST(sc.SHORTAGE_BEFORE - LEAST(sc.SHORTAGE_BEFORE, tc.SAFE_TRANSFERABLE_QTY, tc.MAX_TRANSFER_QTY), 0) AS SHORTAGE_AFTER,
        sc.REFERENCE_DATE AS REFERENCE_DATE,
        DATEADD(day, tc.TRANSIT_DAYS, sc.REFERENCE_DATE) AS ARRIVAL_DATE,
        sc.FIRST_DUE_DATE AS FIRST_CUSTOMER_DUE_DATE,
        CASE WHEN sc.FIRST_DUE_DATE IS NULL THEN NULL ELSE DATEADD(day, tc.TRANSIT_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE END AS ARRIVES_IN_TIME,
        tc.TRANSIT_DAYS AS TRANSIT_OR_LEAD_DAYS,
        LEAST(sc.SHORTAGE_BEFORE, tc.SAFE_TRANSFERABLE_QTY, tc.MAX_TRANSFER_QTY) * tc.COST_PER_UNIT + tc.FIXED_TRANSFER_COST AS ESTIMATED_COST,
        NULL::VARCHAR AS CURRENCY,
        'Transfer cost fields are present but no governed currency attribute exists on INTERPLANT_TRANSFER_OPTION.' AS COST_BASIS,
        FALSE AS COST_COMPARABLE,
        'Transfer leaves source plant ' || tc.ORIGIN_PLANT_ID || ' with ' || (tc.SRC_AVAILABLE_QTY - LEAST(sc.SHORTAGE_BEFORE, tc.SAFE_TRANSFERABLE_QTY, tc.MAX_TRANSFER_QTY)) || ' units available, at or above its safety stock of ' || tc.SRC_SAFETY_STOCK_QTY || '.' AS RISKS_OR_CONSTRAINTS,
        'CURATED.INTERPLANT_TRANSFER_OPTION, CURATED.INVENTORY_SNAPSHOT' AS EVIDENCE_SOURCE
      FROM shortage_ctx sc
      CROSS JOIN transfer_cand tc
      UNION ALL
      SELECT
        'INTERPLANT_TRANSFER', FALSE,
        'No active interplant transfer lane with available source inventory was found for this part and destination plant.',
        NULL, NULL, NULL::NUMBER, NULL::NUMBER, sc.SHORTAGE_BEFORE, sc.SHORTAGE_BEFORE, sc.REFERENCE_DATE, NULL::DATE, sc.FIRST_DUE_DATE, NULL::BOOLEAN, NULL::NUMBER,
        NULL::NUMBER, NULL::VARCHAR, 'No candidate lane/source inventory found.', FALSE, NULL,
        'CURATED.INTERPLANT_TRANSFER_OPTION, CURATED.INVENTORY_SNAPSHOT'
      FROM shortage_ctx sc
      WHERE NOT EXISTS (SELECT 1 FROM transfer_cand)
    ),
    row_alt_supplier AS (
      SELECT
        'ALTERNATE_SUPPLIER' AS INTERVENTION_TYPE,
        (ac.MAX_WEEKLY_SUPPLY_QTY > 0 AND ac.MAX_WEEKLY_SUPPLY_QTY >= COALESCE(ac.MINIMUM_ORDER_QTY,0) AND sc.SHORTAGE_BEFORE > 0
          AND LEAST(sc.SHORTAGE_BEFORE, ac.MAX_WEEKLY_SUPPLY_QTY) > 0
          AND (sc.FIRST_DUE_DATE IS NULL OR DATEADD(day, ac.CONTRACT_LEAD_TIME_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE)
        ) AS FEASIBLE,
        CASE
          WHEN ac.MAX_WEEKLY_SUPPLY_QTY <= 0 THEN 'Supplier ' || ac.SUPPLIER_ID || ' has no supported weekly-supply capacity for this part.'
          WHEN sc.FIRST_DUE_DATE IS NOT NULL AND DATEADD(day, ac.CONTRACT_LEAD_TIME_DAYS, sc.REFERENCE_DATE) > sc.FIRST_DUE_DATE THEN 'Supplier ' || ac.SUPPLIER_ID || ' contract lead time would arrive after the first affected customer due date.'
          ELSE 'Supplier ' || ac.SUPPLIER_ID || ' is an approved, active alternate source with sufficient capacity.'
        END AS REASON,
        NULL::VARCHAR AS SOURCE_LOCATION,
        ac.SUPPLIER_ID AS SOURCE_SUPPLIER,
        ac.MAX_WEEKLY_SUPPLY_QTY AS QUANTITY_AVAILABLE,
        LEAST(sc.SHORTAGE_BEFORE, ac.MAX_WEEKLY_SUPPLY_QTY) AS QUANTITY_USED,
        sc.SHORTAGE_BEFORE AS SHORTAGE_BEFORE,
        GREATEST(sc.SHORTAGE_BEFORE - LEAST(sc.SHORTAGE_BEFORE, ac.MAX_WEEKLY_SUPPLY_QTY), 0) AS SHORTAGE_AFTER,
        sc.REFERENCE_DATE AS REFERENCE_DATE,
        DATEADD(day, ac.CONTRACT_LEAD_TIME_DAYS, sc.REFERENCE_DATE) AS ARRIVAL_DATE,
        sc.FIRST_DUE_DATE AS FIRST_CUSTOMER_DUE_DATE,
        CASE WHEN sc.FIRST_DUE_DATE IS NULL THEN NULL ELSE DATEADD(day, ac.CONTRACT_LEAD_TIME_DAYS, sc.REFERENCE_DATE) <= sc.FIRST_DUE_DATE END AS ARRIVES_IN_TIME,
        ac.CONTRACT_LEAD_TIME_DAYS AS TRANSIT_OR_LEAD_DAYS,
        LEAST(sc.SHORTAGE_BEFORE, ac.MAX_WEEKLY_SUPPLY_QTY) * ac.AGREED_UNIT_PRICE AS ESTIMATED_COST,
        ac.CURRENCY AS CURRENCY,
        'Calculated as quantity used x agreed unit price (SUPPLIER_PART.AGREED_UNIT_PRICE) in the supplier''s governed contract currency.' AS COST_BASIS,
        TRUE AS COST_COMPARABLE,
        'Currency (' || ac.CURRENCY || ') may differ from the requesting supplier''s currency - do not directly compare monetary cost across different currencies without governed FX data.' AS RISKS_OR_CONSTRAINTS,
        'CURATED.SUPPLIER_PART, CURATED.SUPPLIER' AS EVIDENCE_SOURCE
      FROM shortage_ctx sc
      CROSS JOIN alt_supplier_cand ac
      UNION ALL
      SELECT
        'ALTERNATE_SUPPLIER', FALSE,
        'No approved active alternate supplier (with an unexpired contract) was found for this part.',
        NULL, NULL, NULL::NUMBER, NULL::NUMBER, sc.SHORTAGE_BEFORE, sc.SHORTAGE_BEFORE, sc.REFERENCE_DATE, NULL::DATE, sc.FIRST_DUE_DATE, NULL::BOOLEAN, NULL::NUMBER,
        NULL::NUMBER, NULL::VARCHAR, 'No candidate alternate supplier found.', FALSE, NULL,
        'CURATED.SUPPLIER_PART, CURATED.SUPPLIER'
      FROM shortage_ctx sc
      WHERE NOT EXISTS (SELECT 1 FROM alt_supplier_cand)
    ),
    all_rows AS (
      SELECT * FROM row_expedite_current
      UNION ALL
      SELECT * FROM row_expedited_replenishment
      UNION ALL
      SELECT * FROM row_transfer
      UNION ALL
      SELECT * FROM row_alt_supplier
    ),
    ranked AS (
      SELECT
        ar.*,
        RANK() OVER (
          ORDER BY
            IFF(ar.FEASIBLE, 0, 1),
            IFF(COALESCE(ar.SHORTAGE_AFTER,999999999) = 0, 0, 1),
            IFF(COALESCE(ar.ARRIVES_IN_TIME,FALSE), 0, 1),
            COALESCE(ar.SHORTAGE_AFTER, 999999999),
            COALESCE(ar.ARRIVAL_DATE, '9999-12-31'::DATE),
            IFF(ar.COST_COMPARABLE AND ar.ESTIMATED_COST IS NOT NULL, ar.ESTIMATED_COST, 999999999999),
            ar.INTERVENTION_TYPE,
            COALESCE(ar.SOURCE_LOCATION, ''),
            COALESCE(ar.SOURCE_SUPPLIER, '')
        ) AS RECOMMENDATION_RANK
      FROM all_rows ar
    ),
    rank1_count AS (
      SELECT COUNT(*) AS CNT FROM ranked WHERE RECOMMENDATION_RANK = 1
    )
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
      'INTERVENTION_TYPE', r.INTERVENTION_TYPE,
      'FEASIBLE', r.FEASIBLE,
      'REASON', r.REASON,
      'SOURCE_LOCATION', r.SOURCE_LOCATION,
      'SOURCE_SUPPLIER', r.SOURCE_SUPPLIER,
      'QUANTITY_AVAILABLE', r.QUANTITY_AVAILABLE,
      'QUANTITY_USED', r.QUANTITY_USED,
      'SHORTAGE_BEFORE', r.SHORTAGE_BEFORE,
      'SHORTAGE_AFTER', r.SHORTAGE_AFTER,
      'REFERENCE_DATE', r.REFERENCE_DATE::VARCHAR,
      'ARRIVAL_DATE', r.ARRIVAL_DATE::VARCHAR,
      'FIRST_CUSTOMER_DUE_DATE', r.FIRST_CUSTOMER_DUE_DATE::VARCHAR,
      'ARRIVES_IN_TIME', r.ARRIVES_IN_TIME,
      'TRANSIT_OR_LEAD_DAYS', r.TRANSIT_OR_LEAD_DAYS,
      'ESTIMATED_COST', r.ESTIMATED_COST,
      'CURRENCY', r.CURRENCY,
      'COST_BASIS', r.COST_BASIS,
      'COST_COMPARABLE', r.COST_COMPARABLE,
      'RISKS_OR_CONSTRAINTS', r.RISKS_OR_CONSTRAINTS,
      'EVIDENCE_SOURCE', r.EVIDENCE_SOURCE,
      'RECOMMENDATION_RANK', r.RECOMMENDATION_RANK,
      'RECOMMENDED', (r.RECOMMENDATION_RANK = 1 AND r.FEASIBLE AND rc.CNT = 1)
    )) WITHIN GROUP (ORDER BY r.RECOMMENDATION_RANK, r.INTERVENTION_TYPE)
    FROM ranked r, rank1_count rc
  );
  RETURN res;
END;
$$;

/* ===========================================================================
   SECTION D : AGENT UPDATE - ADD THIRD TOOL (preserving Phase 6B exactly)
   Redeploy via CREATE OR REPLACE AGENT with the FULL specification: the two
   existing tools (supply_chain_analytics, supplier_document_search) and all
   their tool_resources are reproduced VERBATIM from the Phase 6B DESCRIBE
   AGENT output; only the new tool, its tool_resource, and extended
   orchestration/response instructions (intervention routing + human-
   approval boundary) are added. Budget (90s/16000 tokens) and
   models.orchestration=auto are unchanged.
   =========================================================================== */

CREATE OR REPLACE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
  COMMENT = 'Phase 7: governed supply-chain intelligence agent combining structured operational analytics (Cortex Analyst / SUPPLY_CHAIN_SEMANTIC_VIEW), supplier contract/SLA evidence (Cortex Search / SUPPLIER_DOCUMENT_SEARCH), and a deterministic read-only intervention decision tool (EVALUATE_SUPPLY_CHAIN_INTERVENTIONS). Reasoning, routing, and evidence-backed answering only - no action execution, Agent Skills, or MCP in this phase. The Agent may EVALUATE and RECOMMEND but cannot EXECUTE any operational intervention.'
  PROFILE = '{"display_name": "SupplyChainIQ Control Tower"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 90
      tokens: 16000

  instructions:
    response: >
      Answer directly and concisely. Distinguish structured operational
      facts (from supply_chain_analytics) from contractual/document facts
      (from supplier_document_search) and from deterministic intervention
      evaluations (from evaluate_supply_chain_interventions) - never merge
      them into a single number. Identify every document-backed claim by
      DOCUMENT_ID and DOCUMENT_TYPE (e.g. "According to DOC000217 (SLA)..."),
      including TITLE or SOURCE_REFERENCE when useful. Never fabricate
      enterprise facts or contractual clauses. Preserve document-scope
      distinctions such as a general/portfolio contract versus a
      part-specific SLA - do not average or collapse different scopes into
      one figure unless they genuinely describe the same scope. Never add
      monetary values across different currencies without governed FX
      conversion data. If requested structured data or documentary evidence
      is unavailable, say so explicitly rather than guessing or using
      general knowledge. The Agent can EVALUATE and RECOMMEND intervention
      options but CANNOT EXECUTE them: every operational intervention
      (expedite, interplant transfer, alternate-supplier switch, PO
      creation) must stop at RECOMMENDATION -> HUMAN APPROVAL REQUIRED ->
      NO EXECUTION CAPABILITY IN THIS PHASE. Never imply that a transfer,
      expedite request, supplier switch, or purchase order was actually
      performed.

    orchestration: >
      Use supply_chain_analytics for structured operational questions:
      Supplier OTD, Shipment Schedule Adherence, Fill Rate, inventory,
      demand, customer-order exposure, purchase orders, shipments, current
      supplier risk, contract/realized/reported lead time, landed cost, and
      sourcing relationships. Do not call supplier_document_search merely
      because a supplier has documents on file.

      Use supplier_document_search for document/contractual questions: SLA
      commitments, contract penalties, quality clauses, escalation terms,
      and other supplier-obligation evidence. Do not use retrieved document
      prose as a substitute for current operational metrics available from
      supply_chain_analytics.

      Use evaluate_supply_chain_interventions for questions asking what can
      be done about a shortage or delivery risk, which interventions are
      feasible, or what is recommended - for example "What can we do about
      the S017 P104 shortage?", "What is the fastest way to protect these
      customer orders?", "Can another plant cover the shortage?", "Can we
      use another supplier?", "Compare our intervention options", "What do
      you recommend and why?". This tool performs the deterministic
      feasibility, quantity, timing, cost, and recommendation-ranking
      calculations itself - never recompute or override its FEASIBLE,
      SHORTAGE_AFTER, ARRIVES_IN_TIME, or RECOMMENDED values yourself. For
      supporting operational context (current OTD, shipment status,
      inventory) additionally use supply_chain_analytics; for supporting
      contractual/SLA/expedite-terms context additionally use
      supplier_document_search - but the intervention tool alone determines
      operational feasibility. Do not let document text determine
      feasibility.

      Use BOTH (or all three) tools for hybrid questions that ask for
      current operational performance, contractual evidence, and/or
      intervention options together. In the answer, clearly separate
      "Current operational facts", "Contractual/document evidence", and
      "Intervention evaluation" - never merge them into one number.

      Operational-vs-contractual mode distinction rule: the
      evaluate_supply_chain_interventions tool identifies the fastest ACTIVE
      structured transport/replenishment option (which may be a different
      transport mode, e.g. Road, than any mode discussed in a supplier
      document). Treat this as an "operational recommendation" based on
      structured feasibility, quantity, timing, safety-stock, capacity, and
      governed cost information only. Contractual applicability of any
      specific transport mode is a separate evidence layer supplied only by
      supplier_document_search - never claim that a document authorizes,
      approves, or is "the same as" the tool's structured recommendation.
      When the operationally recommended mode differs from the mode
      discussed in contract/SLA evidence, explicitly state: (a) which option
      is operationally preferred (from evaluate_supply_chain_interventions),
      (b) which mode the SLA/contract discusses (from
      supplier_document_search), (c) that contractual approval or
      cost-sharing terms for the operationally preferred option have not
      been established from the available documents, and (d) that human
      approval and contract verification are required before execution. Do
      not let this distinction change the tool's deterministic ranking -
      only clarify how the two evidence layers relate in the explanation.

      Lead-time scope rule: DOC000017 states a general/portfolio contract
      lead time; DOC000217 states a P104-specific SLA lead time. If the user
      asks about P104 specifically, prefer the P104-specific SLA evidence.
      If the user asks generally with no part specified and Search retrieves
      both scopes, present them separately as different contractual scopes -
      do not average them or call them contradictory unless the scopes are
      genuinely identical.

      No-hallucination rule: if supplier_document_search finds no supporting
      clause for a requested contractual term (for example a warranty
      period), state explicitly that no supporting clause was found in the
      available documents. Do not answer from general world knowledge.

      Unsupported-metric rule: Inventory Turnover is not available from the
      governed structured model (no canonical costed-inventory/COGS basis).
      If asked for it, state that it is unsupported rather than approximating
      or inventing a proxy metric.

      Currency rule: for Actual Landed Cost or any monetary aggregation,
      use supply_chain_analytics only. Never sum different currencies into
      one total unless governed FX conversion data exists - if a
      cross-currency total is requested, ask for a currency or return a
      currency-separated breakdown instead. Documents may explain penalty or
      cost-sharing terms but must never replace the governed landed-cost
      calculation. For intervention cost comparisons, only compare monetary
      values across options when evaluate_supply_chain_interventions marks
      COST_COMPARABLE = TRUE for both; otherwise present costs separately
      and note they are not directly comparable.

    sample_questions:
      - question: "What is supplier S017's on-time delivery rate?"
      - question: "What SLA commitments exist for supplier S017?"
      - question: "What can we do about the S017 P104 shortage at P01?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "supply_chain_analytics"
        description: >
          Authoritative structured analytics tool for SupplyChainIQ
          operational data. Use for governed metrics and structured facts
          including Supplier OTD, Shipment Schedule Adherence, Fill Rate,
          inventory, demand, customer-order exposure, purchase orders,
          shipments, supplier risk, contract/realized/reported lead time,
          landed cost, sourcing relationships, and other structured facts
          exposed by the SupplyChainIQ Semantic View. Do not derive governed
          operational metrics from supplier-document prose.
    - tool_spec:
        type: "cortex_search"
        name: "supplier_document_search"
        description: >
          Search supplier contracts, SLAs, quality agreements, supplier
          scorecard narratives, procurement policies, and logistics policies
          for contractual, policy, quality, delivery, penalty, escalation,
          and supplier-obligation evidence.
    - tool_spec:
        type: "generic"
        name: "evaluate_supply_chain_interventions"
        description: >
          Authoritative deterministic tool for evaluating supply-chain
          shortage intervention feasibility, quantities, arrival timing,
          cost/currency governance, constraints, and recommendation ranking.
          Given a supplier, part, and destination plant, evaluates whether
          the current in-transit shipment can be rerouted (normally not
          supported), a new expedited replenishment order, an interplant
          transfer from another plant, and an approved alternate supplier -
          and deterministically ranks the feasible options. This tool
          performs the calculation itself; do not recompute or override its
          results.
        input_schema:
          type: object
          properties:
            supplier_id:
              type: string
              description: "Supplier identifier to evaluate interventions for, e.g. 'S017'."
            part_id:
              type: string
              description: "Part identifier experiencing the shortage/risk, e.g. 'P104'."
            destination_plant_id:
              type: string
              description: "Destination plant identifier where the shortage/risk is occurring, e.g. 'P01'."
          required: ["supplier_id", "part_id", "destination_plant_id"]

  tool_resources:
    supply_chain_analytics:
      semantic_view: "SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
    supplier_document_search:
      search_service: "SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH"
      max_results: 5
      title_column: "TITLE"
      id_column: "DOCUMENT_ID"
      columns_and_descriptions:
        SEARCH_TEXT:
          type: "string"
          searchable: true
          filterable: false
          description: "Combined document title, document type, and full supplier-document text."
        DOCUMENT_ID:
          type: "string"
          searchable: false
          filterable: false
          description: "Unique document identifier (e.g. DOC000217). Use to cite the source of any document-backed claim."
        TITLE:
          type: "string"
          searchable: false
          filterable: false
          description: "Human-readable document title."
        SUPPLIER_ID:
          type: "string"
          searchable: false
          filterable: true
          description: "Supplier identifier such as S017. Null for company-wide policy documents (Procurement Policy, Logistics Policy)."
        DOCUMENT_TYPE:
          type: "string"
          searchable: false
          filterable: true
          description: "Document type such as Supplier Contract, SLA, Quality Agreement, Supplier Scorecard Narrative, Procurement Policy, or Logistics Policy."
        EFFECTIVE_DATE:
          type: "date"
          searchable: false
          filterable: true
          description: "Document effective date."
        EXPIRY_DATE:
          type: "date"
          searchable: false
          filterable: true
          description: "Document expiry date."
        SOURCE_REFERENCE:
          type: "string"
          searchable: false
          filterable: false
          description: "Source-system reference URI for the document, useful for citation."
        CONTENT:
          type: "string"
          searchable: false
          filterable: false
          description: "Full original document text (without the title/type prefix used for search)."
    evaluate_supply_chain_interventions:
      identifier: "SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
  $$;

SELECT 'Phase 7B / 15_intervention_decision_tools.sql complete - proceed to structural validation and 16_intervention_decision_validation.sql' AS STATUS;
