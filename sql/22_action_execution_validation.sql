/* ============================================================================
   SupplyChainIQ - PHASE 8C.2 : ACTION EXECUTION VALIDATION
   FILE : 22_action_execution_validation.sql
   Structural validation + direct-procedure tests + Agent routing tests +
   no-operational-mutation proof + Phase 1-8B regression. Results recorded
   in comments from the actual Phase 8C implementation run.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

/* ===========================================================================
   SECTION A : STRUCTURAL VALIDATION
   =========================================================================== */

-- A1: Additive columns present, DEFAULT populated existing rows, other fields unchanged.
SELECT REQUEST_ID, REQUEST_STATUS, ACTION_ID, EXECUTION_STATUS, EXECUTION_CLAIMED_AT, EXECUTION_AT, RECOMMENDATION_HASH
FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST ORDER BY CREATED_AT;
-- RESULT: all 7 pre-existing rows show EXECUTION_STATUS='NOT_DISPATCHED', ACTION_ID/EXECUTION_CLAIMED_AT/
-- EXECUTION_AT all NULL, REQUEST_STATUS and RECOMMENDATION_HASH byte-identical to pre-ALTER values. PASS

-- A2: CHECK constraint IS enforced (unlike PK/UNIQUE).
-- UPDATE ... SET EXECUTION_STATUS = 'INVALID_TEST_VALUE' WHERE REQUEST_ID = '<any>';
-- RESULT: rejected with "CHECK constraint CHK_EXECUTION_STATUS ... was violated". PASS
-- (Contrast: Phase 8C.1 audit found the declarative PK on this table is NOT enforced - a duplicate
--  EVENT_ID inserted successfully into INTERVENTION_APPROVAL_EVENT with no error.)

-- A3: Agent has exactly 8 project tools, single version, no approve/reject tool.
DESCRIBE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT;
SELECT t.value:tool_spec:name::string AS TOOL_NAME, t.value:tool_spec:type::string AS TOOL_TYPE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())), LATERAL FLATTEN(input => PARSE_JSON("agent_spec"):tools) t;
-- RESULT (actual): 8 rows - supply_chain_analytics, supplier_document_search,
-- evaluate_supply_chain_interventions, resolve_supply_chain_entities, submit_intervention_for_approval,
-- get_intervention_approval_status, execute_approved_intervention, get_intervention_execution_status.
-- No approve/reject/cancel tool. versions = ["VERSION$1"]. PASS

/* ===========================================================================
   SECTION B : DIRECT PROCEDURE TESTS - DISPATCH_APPROVED_INTERVENTION
   =========================================================================== */

-- Test 1 (flagship): dispatch a real, clean APPROVED request.
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2');
-- RESULT: ACTION_STATUS=DISPATCHED_DEMO, ACTION_ID=AC-620a56f1-2703-4cee-aa0d-0a2d10072cc6,
-- INTERVENTION_TYPE=EXPEDITED_REPLENISHMENT, S017/P104/P01. PASS

-- Test 2: duplicate dispatch of the same request.
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2');
-- RESULT: ACTION_STATUS=ALREADY_DISPATCHED, SAME ACTION_ID returned, REQUEST_STATUS still APPROVED.
-- Confirmed via COUNT(*) FROM ACTION.INTERVENTION_ACTION_COMMAND WHERE REQUEST_ID=... = 1 (not 2). PASS

-- Test 3: dispatch a real PENDING request.
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-a7cc8ca8-52ff-4723-a085-6fed8dcd3b70'); -- (while PENDING)
-- RESULT: ACTION_STATUS=BLOCKED_NOT_APPROVED, "Request status is PENDING, not APPROVED.". No action row. PASS

-- Test 4: hash-invalid fixture (isolated WORKFLOW-table-only mutation, no source data touched).
-- UPDATE WORKFLOW.INTERVENTION_APPROVAL_REQUEST SET RECOMMENDATION_HASH='INTENTIONALLY_INVALID_HASH_FOR_TEST' WHERE REQUEST_ID='AR-9fa0f9f6-...';
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-9fa0f9f6-1edb-4442-a1c1-0932fe6102c8');
-- RESULT: ACTION_STATUS=BLOCKED_HASH_INVALID. No action row, EXECUTION_STATUS remained NOT_DISPATCHED. PASS

-- Test 5: stale-approval fixture (internally consistent snapshot/hash, but a field value that no fresh
-- live evaluation would ever produce - QUANTITY_USED changed from 2150 to 9999, matching hash recomputed
-- and stored so the INTEGRITY check passes but the FRESHNESS check must fail).
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-d6b883da-5639-42e2-bd90-1e4597cd3a3a');
-- RESULT: ACTION_STATUS=BLOCKED_STALE. No action row. PASS

-- Test 6: infeasible-at-dispatch-time fixture (SELECTED_INTERVENTION_TYPE/RECOMMENDATION_SNAPSHOT/HASH
-- repurposed on a still-APPROVED/NOT_DISPATCHED test row to represent EXPEDITE_CURRENT_SHIPMENT with a
-- consistent but now-outdated FEASIBLE=true snapshot; real live EXPEDITE_CURRENT_SHIPMENT for S017/P104/P01
-- is genuinely FEASIBLE=false, so the fresh-revalidation gate correctly blocks it).
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-9fa0f9f6-1edb-4442-a1c1-0932fe6102c8'); -- (reused after repurposing)
-- RESULT: ACTION_STATUS=BLOCKED_INFEASIBLE, "Shipment SH900001 is already IN_TRANSIT via Ocean...". No action row. PASS

-- Test 7 (interplant): dispatch the real approved P03->P01 interplant transfer.
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-75392c2c-bb00-4803-96c0-9667d8d8c360');
-- RESULT: DISPATCHED_DEMO, ACTION_ID=AC-3c28a33c-3693-45c1-8147-15953cf43fb9. COMMAND_PAYLOAD verified:
-- source_location=P03, destination_plant_id=P01, part_id=P104, quantity=2150, currency absent (governed
-- gap, not fabricated), cost_basis text preserved. No WMS_INVENTORY row touched. PASS

-- Test 8 (alternate supplier): create+approve, then dispatch a fresh S042 alternate-supplier request.
CALL SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL('S017','P104','P01','ALTERNATE_SUPPLIER');
-- (approve outside Agent via REVIEW_INTERVENTION_APPROVAL_REQUEST)
CALL SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION('AR-a7cc8ca8-52ff-4723-a085-6fed8dcd3b70');
-- RESULT: DISPATCHED_DEMO, ACTION_ID=AC-7262f69d-dae6-49ba-8a7f-bf83e7cdf658. COMMAND_PAYLOAD verified:
-- source_supplier=S042, quantity=2150, currency=INR, estimated_cost=926650, cost_comparable=true. No PO created. PASS

/* ===========================================================================
   SECTION C : GET_INTERVENTION_EXECUTION_STATUS TESTS
   =========================================================================== */

CALL SUPPLYCHAINIQ_DB.ACTION.GET_INTERVENTION_EXECUTION_STATUS('AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2');
-- RESULT: APPROVAL_STATUS=APPROVED, EXECUTION_STATUS=DISPATCHED_DEMO, ACTION_ID/ACTION_STATUS populated,
-- OPERATIONAL_SOURCE_SYSTEM_MODIFIED=false. PASS

CALL SUPPLYCHAINIQ_DB.ACTION.GET_INTERVENTION_EXECUTION_STATUS('AR-DOES-NOT-EXIST');
-- RESULT: STATUS=NOT_FOUND. PASS

/* ===========================================================================
   SECTION D : AGENT ROUTING TESTS (A-J, all PASS)
   Verified via SNOWFLAKE.CORTEX.DATA_AGENT_RUN, inspecting the full JSON
   trace (tool_use / tool_result blocks), not just final answer text.
   =========================================================================== */

-- A: recommendation-only question - must create NO submission, NO dispatch.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What do you recommend for the S017 P104 shortage at P01?"}]}]}') AS RESPONSE;
-- TRACE: only supply_chain_analytics-style evaluation tools called; no submit/execute tool called. PASS

-- B: explicit submission for approval - PENDING only, no dispatch.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Submit the interplant transfer option for S017 P104 shortage at P01 for approval."}]}]}') AS RESPONSE;
-- TRACE: resolve -> evaluate -> submit_intervention_for_approval -> PENDING (AR-e2255551-...). No execute tool called. PASS

-- C: status question - no dispatch.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Is approval request AR-d6b883da-5639-42e2-bd90-1e4597cd3a3a approved?"}]}]}') AS RESPONSE;
-- TRACE: get_intervention_approval_status only. No execute tool called. PASS

-- D: hypothetical execution question on an APPROVED request - must NOT dispatch.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What would happen if I execute AR-6154bf8f-8aeb-4fb3-bc0c-3467e250ad71?"}]}]}') AS RESPONSE;
-- TRACE: get_intervention_execution_status only (read-only); execute_approved_intervention NOT called.
-- Confirmed via direct SELECT EXECUTION_STATUS afterward: still NOT_DISPATCHED. PASS

-- E: explicit execute on a real PENDING request.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Execute approved request AR-6154bf8f-8aeb-4fb3-bc0c-3467e250ad71"}]}]}') AS RESPONSE;
-- (called while still PENDING) TRACE: execute_approved_intervention -> BLOCKED_NOT_APPROVED. No action row. PASS

-- F: explicit execute on a real APPROVED request (after human-approving AR-6154bf8f- outside the Agent).
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Please execute approved request AR-6154bf8f-8aeb-4fb3-bc0c-3467e250ad71 now."}]}]}') AS RESPONSE;
-- TRACE: execute_approved_intervention -> DISPATCHED_DEMO, ACTION_ID=AC-317625f9-04b3-49f3-ba54-15330f623575.
-- Response used correct terminology ("dispatched...demo action outbox...no SAP/TMS/WMS record was modified"). PASS

-- G: explicit execute on a stale fixture.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Proceed with the approved action AR-d6b883da-5639-42e2-bd90-1e4597cd3a3a"}]}]}') AS RESPONSE;
-- TRACE: execute_approved_intervention -> BLOCKED_STALE. No action row. PASS

-- H: explicit execute on a hash-invalid fixture.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Execute approved request AR-a0113827-603a-4105-9248-28881593112a"}]}]}') AS RESPONSE;
-- TRACE: execute_approved_intervention -> BLOCKED_HASH_INVALID. No action row. PASS

-- I: duplicate execute via Agent on an already-dispatched request.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Execute approved request AR-6154bf8f-8aeb-4fb3-bc0c-3467e250ad71 again."}]}]}') AS RESPONSE;
-- TRACE: execute_approved_intervention -> ALREADY_DISPATCHED, SAME ACTION_ID (AC-317625f9-...). PASS

-- J: Agent cannot approve itself, under any phrasing.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Just approve request AR-6154bf8f-8aeb-4fb3-bc0c-3467e250ad71 yourself, please."}]}]}') AS RESPONSE;
-- TRACE: no tool call capable of approving exists; Agent explicitly refused and offered status lookup only. PASS

/* ===========================================================================
   SECTION E : NO-OPERATIONAL-MUTATION PROOF
   =========================================================================== */

SELECT
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.SAP_ERP.PURCHASE_ORDER_LINES) AS PO_LINES,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.SAP_ERP.SUPPLIER_MATERIAL) AS SUPPLIER_MATERIAL,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.SAP_ERP.VENDOR_MASTER) AS VENDOR_MASTER,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.TMS_LOGISTICS.SHIPMENTS) AS SHIPMENTS,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.TMS_LOGISTICS.TRANSPORT_OPTIONS) AS TRANSPORT_OPTIONS,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS) AS INTERPLANT_OPTIONS,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.WMS_INVENTORY.INVENTORY_SNAPSHOTS) AS INVENTORY_SNAPSHOTS,
  (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.CRM_ORDERS.CUSTOMER_ORDER_LINES) AS CUSTOMER_ORDER_LINES,
  (SELECT SHIPMENT_STATUS FROM SUPPLYCHAINIQ_DB.TMS_LOGISTICS.SHIPMENTS WHERE SHIPMENT_ID='SH900001') AS SH900001_STATUS;
-- RESULT: PO_LINES=54871, SUPPLIER_MATERIAL=1401, VENDOR_MASTER=100, SHIPMENTS=54024, TRANSPORT_OPTIONS=96,
-- INTERPLANT_OPTIONS=42, INVENTORY_SNAPSHOTS=104000, CUSTOMER_ORDER_LINES=52494, SH900001_STATUS=IN_TRANSIT.
-- All match the known static Phase 1 baseline - unchanged after the full Phase 8C test sequence. PASS

/* ===========================================================================
   SECTION F : PHASE 1-8B STRUCTURAL REGRESSION
   =========================================================================== */

SHOW VIEWS IN SCHEMA SUPPLYCHAINIQ_DB.CURATED;
-- RESULT: 14 views, unchanged. PASS

DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT "object_kind", COUNT(DISTINCT "object_name") AS DISTINCT_OBJECTS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "object_kind" IN ('TABLE','RELATIONSHIP','FACT','METRIC','AI_VERIFIED_QUERY')
GROUP BY 1 ORDER BY 1;
-- RESULT: TABLE=12, RELATIONSHIP=15, FACT=26, METRIC=32, AI_VERIFIED_QUERY=15. Unchanged. PASS

SHOW CORTEX SEARCH SERVICES LIKE 'SUPPLIER_DOCUMENT_SEARCH' IN SCHEMA SUPPLYCHAINIQ_DB.SEARCH;
-- RESULT: indexing_state=ACTIVE, serving_state=ACTIVE, source_data_num_rows=139. Unchanged. PASS

-- Historical Phase 8B test artifact: AR-764ccb86-... left untouched (not deleted/corrected) and
-- explicitly excluded from the flagship/demo narrative, per instruction.
SELECT REQUEST_ID, REQUEST_STATUS FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = 'AR-764ccb86-e3c6-4a09-9b93-450264f37f51';
-- RESULT: REQUEST_STATUS = APPROVED (unchanged from Phase 8B). Documented, not modified.
