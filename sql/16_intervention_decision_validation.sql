/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 7B : INTERVENTION DECISION TOOL VALIDATION
   FILE    : 16_intervention_decision_validation.sql
   PURPOSE : Structural validation of the third Agent tool, direct procedure
             tests (deterministic, pre-Agent), Agent-level tests via
             SNOWFLAKE.CORTEX.DATA_AGENT_RUN, and Phase 1-6 regression.

   SAFETY  : Read-only except for the isolated synthetic CTE fixtures in
             Section B (literal VALUES, not touching any real table).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : AGENT STRUCTURAL VALIDATION
   =========================================================================== */
DESCRIBE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT;
/* Confirmed via agent_spec JSON:
   - exactly 3 tools: supply_chain_analytics, supplier_document_search,
     evaluate_supply_chain_interventions                              PASS
   - supply_chain_analytics and supplier_document_search configs are
     byte-identical to the Phase 6B DESCRIBE AGENT output               PASS
   - evaluate_supply_chain_interventions: type=generic, input_schema has
     supplier_id/part_id/destination_plant_id (all string, all required) PASS
   - tool_resources.evaluate_supply_chain_interventions: identifier=
     SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS,
     type=procedure, execution_environment warehouse=COMPUTE_WH,
     query_timeout=60                                                   PASS
   - models.orchestration=auto, budget seconds=90/tokens=16000 unchanged PASS
   - no code_execution, web_search, MCP, or other tool added             PASS
   - single version VERSION$1, DEFAULT/FIRST/LAST all point to it        PASS
*/

/* ===========================================================================
   SECTION B : DIRECT PROCEDURE VALIDATION (pre-Agent, deterministic)
   =========================================================================== */

-- TEST 1 / 12 (flagship): S017/P104/P01
-- Expected: EXPEDITED_REPLENISHMENT feasible/recommended (rank 1), arrives
-- 2026-08-18, shortage_after=0; INTERPLANT_TRANSFER (P03) feasible rank 2,
-- cost=121750 (no currency); ALTERNATE_SUPPLIER (S042) feasible rank 3,
-- cost=926650 INR; EXPEDITE_CURRENT_SHIPMENT infeasible rank 4 (SH900001,
-- 5-day delay). RESULT: exactly as expected. PASS.
CALL SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS('S017','P104','P01');

-- TEST: shortage-context recalculation (reconfirms Phase 7A invariants live)
-- Expected: available=8200, safety=3000, usable=5200, required=7350,
-- first_due=2026-08-27, exposure=4200000, shortage_before=2150.
WITH ref AS (
  SELECT DATASET_ANCHOR_DATE AS REFERENCE_DATE FROM SUPPLYCHAINIQ_DB.PUBLIC.DATASET_METADATA ORDER BY VERSION DESC LIMIT 1
),
dest_inv AS (
  SELECT i.AVAILABLE_QTY, i.SAFETY_STOCK_QTY, GREATEST(i.AVAILABLE_QTY - i.SAFETY_STOCK_QTY,0) AS USABLE_QTY
  FROM SUPPLYCHAINIQ_DB.CURATED.INVENTORY_SNAPSHOT i
  WHERE i.PART_ID = 'P104' AND i.PLANT_ID = 'P01'
  QUALIFY ROW_NUMBER() OVER (ORDER BY i.SNAPSHOT_DATE DESC) = 1
),
demand_ctx AS (
  SELECT SUM(GREATEST(c.ORDERED_QTY - c.FULFILLED_QTY,0)) AS REQUIRED_QTY, MIN(c.DUE_DATE) AS FIRST_DUE_DATE, SUM(c.ORDER_VALUE) AS EXPOSURE_VALUE
  FROM SUPPLYCHAINIQ_DB.CURATED.CUSTOMER_ORDER_LINE c, ref
  WHERE c.PART_ID = 'P104' AND c.PLANT_ID = 'P01'
    AND c.ORDER_STATUS NOT IN ('CANCELLED','FULFILLED')
    AND c.DUE_DATE BETWEEN ref.REFERENCE_DATE AND DATEADD(day,14,ref.REFERENCE_DATE)
)
SELECT ref.REFERENCE_DATE, dest_inv.AVAILABLE_QTY, dest_inv.SAFETY_STOCK_QTY, dest_inv.USABLE_QTY,
       demand_ctx.REQUIRED_QTY, demand_ctx.FIRST_DUE_DATE, demand_ctx.EXPOSURE_VALUE,
       GREATEST(demand_ctx.REQUIRED_QTY - dest_inv.USABLE_QTY, 0) AS SHORTAGE_BEFORE
FROM ref, dest_inv, demand_ctx;

-- TEST 6/7 (natural negative control): S099/P746/P11 - single-supplier part
-- with no alternate; destination plant with no transfer-lane candidate.
-- Expected: ALTERNATE_SUPPLIER and INTERPLANT_TRANSFER both FEASIBLE=false
-- with explicit "no candidate found" reasons.
-- Also exercises TEST 2 (expedite infeasible - arrives after due date) and
-- TEST 11 (all-options-infeasible: zero feasible/recommended rows).
-- RESULT: all 4 rows FEASIBLE=false, zero RECOMMENDED=true. PASS.
CALL SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS('S099','P746','P11');

-- TEST 4 (isolated synthetic fixture): safety-stock protection
-- Proves GREATEST(available - safety, 0) never goes negative and blocks a
-- transfer that would breach source safety stock (available=0 <= safety=460,
-- matching the real P711/P01 data point found during Phase 7B audit).
-- Expected: SAFE_TRANSFERABLE_QTY=0, QUANTITY_USED=0, SHORTAGE_AFTER=2150 (unresolved).
-- RESULT: exactly as expected. PASS.
WITH synthetic_transfer_fixture AS (
  SELECT * FROM (VALUES
    ('safety_stock_blocks_transfer', 0::NUMBER, 460::NUMBER, 5000::NUMBER, 2150::NUMBER)
  ) AS t(LABEL, AVAILABLE_QTY, SAFETY_STOCK_QTY, MAX_TRANSFER_QTY, SHORTAGE)
)
SELECT
  LABEL,
  GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0) AS SAFE_TRANSFERABLE_QTY,
  LEAST(SHORTAGE, GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0), MAX_TRANSFER_QTY) AS QUANTITY_USED,
  GREATEST(SHORTAGE - LEAST(SHORTAGE, GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0), MAX_TRANSFER_QTY), 0) AS SHORTAGE_AFTER
FROM synthetic_transfer_fixture;

-- TEST 5 (isolated synthetic fixture): lane-capacity constraint
-- Proves LEAST(shortage, safe_transferable, lane_capacity) never exceeds
-- MAX_TRANSFER_QTY even when source stock is abundant, producing a genuine
-- residual shortage (partial coverage) rather than silently ignoring the cap.
-- Expected: QUANTITY_USED=500 (capacity-bound, not 2150), SHORTAGE_AFTER=1650.
-- RESULT: exactly as expected. PASS.
WITH synthetic_transfer_fixture AS (
  SELECT * FROM (VALUES
    ('lane_capacity_constrains_transfer', 8000::NUMBER, 2000::NUMBER, 500::NUMBER, 2150::NUMBER)
  ) AS t(LABEL, AVAILABLE_QTY, SAFETY_STOCK_QTY, MAX_TRANSFER_QTY, SHORTAGE)
)
SELECT
  LABEL,
  GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0) AS SAFE_TRANSFERABLE_QTY,
  LEAST(SHORTAGE, GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0), MAX_TRANSFER_QTY) AS QUANTITY_USED,
  GREATEST(SHORTAGE - LEAST(SHORTAGE, GREATEST(AVAILABLE_QTY - SAFETY_STOCK_QTY, 0), MAX_TRANSFER_QTY), 0) AS SHORTAGE_AFTER
FROM synthetic_transfer_fixture;

/* ===========================================================================
   SECTION C : AGENT-LEVEL TESTS (SNOWFLAKE.CORTEX.DATA_AGENT_RUN)
   =========================================================================== */

-- TEST 12 (flagship end-to-end Agent recommendation)
-- Expected: evaluate_supply_chain_interventions called; answer explains
-- shortage, all 4 candidates, feasibility, quantity, timing, residual
-- shortage, cost limitations, recommendation + rationale, human-approval
-- requirement.
-- RESULT: tool called successfully on first attempt; Rank-1 recommendation
-- (EXPEDITED_REPLENISHMENT) correctly explained; cost incomparability
-- across currencies explicitly noted; human-approval boundary stated;
-- "no action has been or will be executed" stated. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What can we do about the S017 P104 shortage at P01? Compare the feasible interventions and recommend the best option."}]}], "stream": false}'
) AS FLAGSHIP_AGENT_TEST;

-- HYBRID CONTRACT TEST: decision procedure + supplier_document_search
-- Expected: decision procedure determines feasibility; DOC000217 provides
-- contractual expedited-freight evidence; sources kept separate.
-- RESULT: Agent called both tools; explicitly reconciled the structured
-- tool's fastest-lane pick (1.6x/3-day Road) against the SLA's
-- contractually-approved lane (2.6x/4-day Air) as "different bases,"
-- confirming document text did NOT override the deterministic feasibility
-- calculation. Human-approval boundary restated. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What can we do about the S017 P104 shortage, and what does the SLA say about expedited freight?"}]}], "stream": false}'
) AS HYBRID_CONTRACT_TEST;

/* ===========================================================================
   SECTION D : PHASE 6 REGRESSION (5 spot checks, must remain unchanged)
   =========================================================================== */

-- Overall OTD (structured only) - expected ~75.19% (0.751929), no intervention tool call.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is our overall supplier OTD?"}]}], "stream": false}'
) AS REGRESSION_OVERALL_OTD;

-- S017 OTD (structured only) - expected ~49.35% (0.493506).
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is supplier S017''s on-time delivery rate?"}]}], "stream": false}'
) AS REGRESSION_S017_OTD;

-- Search penalty question (search only) - expected DOC000217 (2%/wk, 10% cap).
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What penalty applies if supplier S017 delivers P104 late?"}]}], "stream": false}'
) AS REGRESSION_PENALTY_SEARCH;

-- Warranty negative control - expected explicit "no clause found", no hallucination.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What warranty period does S017''s contract specify?"}]}], "stream": false}'
) AS REGRESSION_WARRANTY_NEGATIVE_CONTROL;

-- OTD vs contractual OTD hybrid - expected 49.4% actual clearly separated from 92%/95% targets.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How is supplier S017 performing against its contractual delivery commitments?"}]}], "stream": false}'
) AS REGRESSION_OTD_VS_CONTRACTUAL_HYBRID;

/* ===========================================================================
   SECTION E : PHASE 1-5 REGRESSION (structural counts, unchanged)
   =========================================================================== */
DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT
  (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'TABLE') AS TABLES,
  (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'RELATIONSHIP') AS RELATIONSHIPS,
  (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'DIMENSION' AND "property" = 'TABLE') AS DIMENSIONS,
  (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'FACT' AND "property" = 'TABLE') AS FACTS,
  (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'METRIC' AND "property" = 'TABLE') AS METRICS,
  (SELECT COUNT(DISTINCT "object_name") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "object_kind" = 'AI_VERIFIED_QUERY') AS VQS;
-- Expected: 12/15/70/26/32/15 - unchanged. PASS.

SELECT COUNT(*) AS CURATED_VIEW_COUNT FROM SUPPLYCHAINIQ_DB.INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'CURATED';
-- Expected: 14 - unchanged. PASS.

SHOW CORTEX SEARCH SERVICES IN SCHEMA SUPPLYCHAINIQ_DB.SEARCH;
-- Expected: ACTIVE/ACTIVE, source_data_num_rows=139 - unchanged. PASS.

SELECT 'Phase 7B / 16_intervention_decision_validation.sql complete - all direct-procedure and Agent-level tests PASS, Phase 1-6 regression clean.' AS STATUS;
