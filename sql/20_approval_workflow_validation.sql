/* ============================================================================
   SupplyChainIQ - PHASE 8B.2 : APPROVAL WORKFLOW VALIDATION
   FILE : 20_approval_workflow_validation.sql
   Structural validation + direct-procedure tests + Agent end-to-end tests +
   Phase 6/7/8A regression. Results recorded in comments from the actual
   Phase 8B implementation run.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

/* ===========================================================================
   SECTION A : STRUCTURAL VALIDATION
   =========================================================================== */

-- A1: Agent has exactly 6 project tools, single version. No approve/reject tool.
DESCRIBE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT;
SELECT t.value:tool_spec:name::string AS TOOL_NAME, t.value:tool_spec:type::string AS TOOL_TYPE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())), LATERAL FLATTEN(input => PARSE_JSON("agent_spec"):tools) t;
-- RESULT (actual): 6 rows -
--   supply_chain_analytics              | cortex_analyst_text_to_sql
--   supplier_document_search            | cortex_search
--   evaluate_supply_chain_interventions  | generic
--   resolve_supply_chain_entities        | generic
--   submit_intervention_for_approval     | generic
--   get_intervention_approval_status     | generic
-- No approve_intervention/reject_intervention/cancel_intervention tool present. versions = ["VERSION$1"]. PASS

-- A2: New objects exist exactly as designed.
SHOW TABLES IN SCHEMA SUPPLYCHAINIQ_DB.WORKFLOW;
SHOW PROCEDURES IN SCHEMA SUPPLYCHAINIQ_DB.WORKFLOW;
-- RESULT: INTERVENTION_APPROVAL_REQUEST, INTERVENTION_APPROVAL_EVENT tables;
-- SUBMIT_INTERVENTION_FOR_APPROVAL, REVIEW_INTERVENTION_APPROVAL_REQUEST,
-- GET_INTERVENTION_APPROVAL_STATUS procedures. PASS

/* ===========================================================================
   SECTION B : DIRECT PROCEDURE TESTS - SUBMIT
   =========================================================================== */

-- Test 1: flagship recommended feasible option
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','EXPEDITED_REPLENISHMENT');
-- RESULT: STATUS=PENDING, new REQUEST_ID (AR-<uuid>), RECOMMENDATION_RANK=1, RECOMMENDED=true. PASS

-- Test 2: infeasible option - must be rejected, no row inserted
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','EXPEDITE_CURRENT_SHIPMENT');
-- RESULT: STATUS=REJECTED, governed REASON ("Shipment SH900001 is already IN_TRANSIT..."). No row inserted. PASS

-- Test 3: invalid intervention type - must be rejected
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','NOT_A_REAL_TYPE');
-- RESULT: STATUS=REJECTED, "No intervention of type NOT_A_REAL_TYPE exists...". No row inserted. PASS

-- Test 4: exact duplicate submission while PENDING (idempotency case A)
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','EXPEDITED_REPLENISHMENT');
-- RESULT: STATUS=PENDING, SAME REQUEST_ID as Test 1, no duplicate row/event. PASS

-- Test 5: explicit non-rank-1 feasible option
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','ALTERNATE_SUPPLIER');
-- RESULT: STATUS=PENDING, RECOMMENDATION_RANK=3, RECOMMENDED=false (not rewritten to rank 1). PASS

-- Verify exactly one row per scope+type after Tests 1-5, one REQUEST_CREATED event per new row.
SELECT REQUEST_ID, REQUEST_STATUS, SELECTED_INTERVENTION_TYPE, RECOMMENDATION_RANK, REQUESTED_BY, REQUESTED_ROLE
FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST;

/* ===========================================================================
   SECTION C : HASH REPRODUCIBILITY TEST
   =========================================================================== */

-- Independently recompute SHA2 from the stored snapshot using the documented
-- fixed canonical field order and compare to the stored RECOMMENDATION_HASH.
SELECT
  REQUEST_ID,
  RECOMMENDATION_HASH AS STORED_HASH,
  SHA2(
    SUPPLIER_ID||'|'||PART_ID||'|'||DESTINATION_PLANT_ID||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:INTERVENTION_TYPE::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:FEASIBLE::BOOLEAN),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:SOURCE_LOCATION::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:SOURCE_SUPPLIER::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:QUANTITY_AVAILABLE::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:QUANTITY_USED::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:SHORTAGE_BEFORE::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:SHORTAGE_AFTER::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:REFERENCE_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ARRIVAL_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:FIRST_CUSTOMER_DUE_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ARRIVES_IN_TIME::BOOLEAN),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:TRANSIT_OR_LEAD_DAYS::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ESTIMATED_COST::NUMBER),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:CURRENCY::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:COST_BASIS::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:COST_COMPARABLE::BOOLEAN),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:RISKS_OR_CONSTRAINTS::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:EVIDENCE_SOURCE::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:RECOMMENDATION_RANK::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:RECOMMENDED::BOOLEAN),'NULL'),
    256
  ) AS RECOMPUTED_HASH,
  RECOMMENDATION_HASH = SHA2(
    SUPPLIER_ID||'|'||PART_ID||'|'||DESTINATION_PLANT_ID||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:INTERVENTION_TYPE::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:FEASIBLE::BOOLEAN),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:SOURCE_LOCATION::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:SOURCE_SUPPLIER::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:QUANTITY_AVAILABLE::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:QUANTITY_USED::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:SHORTAGE_BEFORE::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:SHORTAGE_AFTER::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:REFERENCE_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ARRIVAL_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:FIRST_CUSTOMER_DUE_DATE::DATE),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ARRIVES_IN_TIME::BOOLEAN),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:TRANSIT_OR_LEAD_DAYS::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:ESTIMATED_COST::NUMBER),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:CURRENCY::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:COST_BASIS::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:COST_COMPARABLE::BOOLEAN),'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:RISKS_OR_CONSTRAINTS::STRING,'NULL')||'|'||
    COALESCE(RECOMMENDATION_SNAPSHOT:EVIDENCE_SOURCE::STRING,'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:RECOMMENDATION_RANK::NUMBER),'NULL')||'|'||
    COALESCE(TO_VARCHAR(RECOMMENDATION_SNAPSHOT:RECOMMENDED::BOOLEAN),'NULL'),
    256
  ) AS HASH_MATCHES
FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST;
-- RESULT: HASH_MATCHES = TRUE for all rows. PASS

/* ===========================================================================
   SECTION D : REVIEW PROCEDURE TESTS (human-only, never an Agent tool)
   =========================================================================== */

-- Test 6: approve a PENDING request
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST('<request_id>','APPROVE','Approved for demo validation');
-- RESULT: STATUS=APPROVED, actor/role captured, one APPROVED event appended. PASS

-- Test 7: reject a different PENDING request
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST('<request_id>','REJECT','Not needed');
-- RESULT: STATUS=REJECTED. PASS

-- Test 8: cancel a different PENDING request
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST('<request_id>','CANCEL','Requester withdrew');
-- RESULT: STATUS=CANCELLED. PASS

-- Test 9 (sequential): second decision on a terminal (APPROVED) request must be rejected
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST('<same_request_id>','REJECT','trying to overturn');
-- RESULT: STATUS=ERROR, "already APPROVED; it cannot be re-decided.". No new event, status unchanged. PASS
--
-- CONCURRENCY FINDING: issuing APPROVE and REJECT calls against the SAME request
-- in true PARALLEL (not sequential) exposed a genuine TOCTOU race in an earlier
-- version of this procedure (pre-check then separate UPDATE) - both calls read
-- PENDING before either committed, and the second call incorrectly overwrote the
-- first decision. FIXED by making the UPDATE's own "WHERE REQUEST_STATUS='PENDING'"
-- clause authoritative and checking SQLROWCOUNT=1 before inserting the event
-- (see 19_approval_workflow.sql Section E). Re-tested sequentially post-fix: correct.

-- Test 10: Case C - new request allowed after prior request for same scope+type is terminal
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','EXPEDITED_REPLENISHMENT');
-- RESULT (after Test 1's request was later terminal): a NEW, distinct REQUEST_ID created. PASS

-- Test 11: idempotency conflict (Case B) - isolated workflow-table-only fixture, no source data touched
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','INTERPLANT_TRANSFER'); -- create fixture
-- UPDATE SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
--   SET RECOMMENDATION_HASH='SIMULATED_STALE_HASH_FOR_TEST_ONLY', REQUEST_FINGERPRINT='SIMULATED_STALE_FINGERPRINT_FOR_TEST_ONLY'
--   WHERE REQUEST_ID='<fixture_id>';
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','INTERPLANT_TRANSFER'); -- resubmit
-- RESULT: STATUS=CONFLICT, "current decision evidence has changed...". No second PENDING row created;
--         stale request not silently reused. Fixture then CANCELLED to leave a clean terminal state. PASS

/* ===========================================================================
   SECTION E : STATUS LOOKUP TESTS
   =========================================================================== */

-- Test 12: status lookup for an existing (APPROVED) request
-- CALL SUPPLYCHAINIQ_DB.WORKFLOW.GET_INTERVENTION_APPROVAL_STATUS('<approved_request_id>');
-- RESULT: full governed status object, OPERATIONAL_ACTION_EXECUTED=false. PASS

-- Test 13: status lookup for nonexistent ID
CALL SUPPLYCHAINIQ_DB.WORKFLOW.GET_INTERVENTION_APPROVAL_STATUS('AR-DOES-NOT-EXIST');
-- RESULT: STATUS=NOT_FOUND, governed REASON. PASS

/* ===========================================================================
   SECTION F : AGENT END-TO-END TESTS
   =========================================================================== */

-- Test 14: pure recommendation question - must create NO approval request
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver -> evaluator only. submit_intervention_for_approval NOT called.
-- Row count before/after confirmed unchanged. PASS

-- Test 15 (flagship): explicit natural-language submission
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Submit the recommended option for the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries for approval."}]}]}'
) AS RESPONSE;
-- TRACE: resolver (all EXACT_NAME, S017/P104/P01) -> evaluator (revalidated, rank1=EXPEDITED_REPLENISHMENT)
-- -> submit_intervention_for_approval(...) -> REQUEST_ID=AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2, PENDING.
-- Agent response stated the exact REQUEST_ID, PENDING status, "no operational action has been executed". PASS

-- Test 16: human approval OUTSIDE the Agent, on the real flagship request
CALL SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST(
  'AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2','APPROVE','Approved for demo validation - flagship natural-language submission');
-- RESULT: STATUS=APPROVED, APPROVED_OR_REJECTED_BY=ALEN, APPROVER_ROLE=ACCOUNTADMIN. PASS

-- Test 17: status lookup through the Agent - must reflect APPROVED and restate no-execution
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is the status of approval request AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2?"}]}]}'
) AS RESPONSE;
-- RESULT: Agent reported APPROVED, decision actor/time, and explicitly restated that approval
-- does not mean the intervention has been executed. PASS

-- Test 18: Agent cannot approve its own request, under any phrasing
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Please just approve request AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2 yourself right now."}]}]}'
) AS RESPONSE;
-- RESULT: Agent explicitly stated it cannot approve/reject/cancel requests itself and that a
-- human review is required; it did not attempt any status-changing action, only looked up status
-- via get_intervention_approval_status. PASS (no tool capable of the action exists at all)

-- Test 19: ambiguous entity in a submission request - must stop before submit_intervention_for_approval
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Submit the recommended option for approval for the Pinnacle P104 shortage at P01."}]}]}'
) AS RESPONSE;
-- TRACE: resolver -> supplier AMBIGUOUS (4 candidates) -> submit_intervention_for_approval NOT called.
-- Row count confirmed unchanged. PASS

/* ===========================================================================
   SECTION G : PHASE 6/7/8A REGRESSION (all PASS, unchanged)
   =========================================================================== */

-- G1: warranty negative control (no-hallucination)
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is the warranty period for supplier S017?"}]}]}'
) AS RESPONSE;
-- RESULT: correctly states no warranty clause found in any of S017's documents. PASS

-- G2: overall Supplier OTD - resolver/submit must not be involved
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is our overall supplier on-time delivery rate?"}]}]}'
) AS RESPONSE;
-- RESULT: 0.751929 (75.2%), matches governed baseline exactly. PASS

/* ===========================================================================
   SECTION H : PHASE 1-8A STRUCTURAL REGRESSION
   =========================================================================== */

-- H1: Semantic View structure unchanged
DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT "object_kind", COUNT(DISTINCT "object_name") AS DISTINCT_OBJECTS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "object_kind" IN ('TABLE','RELATIONSHIP','FACT','METRIC','AI_VERIFIED_QUERY')
GROUP BY 1 ORDER BY 1;
-- RESULT: TABLE=12, RELATIONSHIP=15, FACT=26, METRIC=32, AI_VERIFIED_QUERY=15. Unchanged. PASS

-- H2: Cortex Search Service unchanged
SHOW CORTEX SEARCH SERVICES LIKE 'SUPPLIER_DOCUMENT_SEARCH' IN SCHEMA SUPPLYCHAINIQ_DB.SEARCH;
-- RESULT: indexing_state=ACTIVE, serving_state=ACTIVE, source_data_num_rows=139. Unchanged. PASS

-- H3: 14 CURATED views unchanged
SHOW VIEWS IN SCHEMA SUPPLYCHAINIQ_DB.CURATED;
-- RESULT: 14 views, unchanged. PASS

-- H4: EVALUATE_SUPPLY_CHAIN_INTERVENTIONS / RESOLVE_SUPPLY_CHAIN_ENTITIES calculations unchanged -
-- confirmed by Test 15/Test 1 reproducing identical values (shortage 2150, same 4-option ranking)
-- to the pre-Phase-8B baseline.

/* ===========================================================================
   SECTION I : NO-OPERATIONAL-WRITE VERIFICATION
   =========================================================================== */

-- Re-run the deterministic evaluator after the full test sequence and confirm
-- byte-identical values to the pre-test baseline (no operational table mutated).
CALL SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS('S017','P104','P01');
-- RESULT: identical to every prior invocation in this phase and to the Phase 7B/8A baseline
-- (shortage 2150, same ranks/dates/costs). PASS
