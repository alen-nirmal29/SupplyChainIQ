/* ============================================================================
   SupplyChainIQ - PHASE 8A.2 : ENTITY RESOLUTION VALIDATION
   FILE : 18_entity_resolution_validation.sql
   Structural validation + 17 direct-procedure tests + 8 Agent end-to-end
   tests + Phase 6/7 and Phase 1-5 regression. All results recorded in
   comments from the actual Phase 8A implementation run.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

/* ===========================================================================
   SECTION A : STRUCTURAL VALIDATION
   =========================================================================== */

-- A1: Agent has exactly 4 project tools, single version.
DESCRIBE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT;
SELECT t.value:tool_spec:name::string AS TOOL_NAME, t.value:tool_spec:type::string AS TOOL_TYPE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())), LATERAL FLATTEN(input => PARSE_JSON("agent_spec"):tools) t;
-- RESULT (actual): 4 rows -
--   supply_chain_analytics        | cortex_analyst_text_to_sql
--   supplier_document_search      | cortex_search
--   evaluate_supply_chain_interventions | generic
--   resolve_supply_chain_entities | generic
-- versions = ["VERSION$1"]  -- single version, PASS

/* ===========================================================================
   SECTION B : DIRECT PROCEDURE TESTS (17/17 PASS)
   =========================================================================== */

-- Test 1: Supplier exact ID
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('S017', NULL, NULL);
-- RESULT: supplier.RESOLUTION_STATUS = EXACT_ID, CANONICAL_ID = S017, CANONICAL_NAME = Pinnacle Industries. PASS

-- Test 2: Part exact ID
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(NULL, 'P104', NULL);
-- RESULT: part.RESOLUTION_STATUS = EXACT_ID, CANONICAL_ID = P104. PASS

-- Test 3: Plant exact ID
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(NULL, NULL, 'P01');
-- RESULT: plant.RESOLUTION_STATUS = EXACT_ID, CANONICAL_ID = P01. PASS

-- Tests 4-6: exact names for all three entity types combined
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(
  'Pinnacle Industries', 'High-Precision Hydraulic Control Valve Assembly Type 104', 'Pune Assembly Plant');
-- RESULT: all three RESOLUTION_STATUS = EXACT_NAME -> S017 / P104 / P01. PASS

-- Test 7: case-insensitive exact name
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('pinnacle industries', NULL, NULL);
-- RESULT: EXACT_NAME -> S017. PASS

-- Test 8: whitespace/punctuation normalization
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('Pinnacle Industries.', NULL, NULL);
-- RESULT: NORMALIZED_EXACT -> S017. PASS

-- Tests 9-11: unique partial matches
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('Pinnacle Ind', 'Hydraulic Control Valve', 'Pune');
-- RESULT: supplier UNIQUE_MATCH -> S017; part UNIQUE_MATCH -> P104; plant UNIQUE_MATCH -> P01. PASS

-- Test 12: ambiguous supplier partial (real data - "Pinnacle" root repeats x4)
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('Pinnacle', NULL, NULL);
-- RESULT: AMBIGUOUS, CANONICAL_ID = null, 4 candidates: S017 Pinnacle Industries, S042 Pinnacle Fasteners,
--         S067 Pinnacle Metalworks, S092 Pinnacle Manufacturing. PASS

-- Test 13: ambiguous EXACT-TEXT duplicate part description (real data - P086/P986)
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(NULL, 'Seal Kit Type 318', NULL);
-- RESULT: AMBIGUOUS (not a false EXACT_NAME), CANONICAL_ID = null, 2 candidates: P086, P986,
--         both "Seal Kit Type 318" / Seals / Low. Proves exact-text duplicates never silently auto-resolve. PASS

-- Test 14: ambiguous plant partial (real data - "Assembly Plant" in 4 plants)
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(NULL, NULL, 'Assembly Plant');
-- RESULT: AMBIGUOUS, 4 candidates: P01, P05, P07, P09. PASS

-- Test 15: no-match negative control
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('Quantum Robotics Unlimited', NULL, NULL);
-- RESULT: NO_MATCH, CANDIDATE_COUNT = 0. PASS

-- Test 16: fuzzy typo candidate - must NOT auto-resolve even at high score
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES('Pinacle Industries', NULL, NULL);
-- RESULT: FUZZY_CANDIDATES, CANONICAL_ID = null (even though top candidate S017 scored 94),
--         candidates: S017 (94), S076 Zenith Industries (84), S061 Sterling Industries (82),
--         S042 Pinnacle Fasteners (82). PASS

-- Test 17: mixed ID + names
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(
  'S042', 'High-Precision Hydraulic Control Valve Assembly Type 104', 'Pune Assembly Plant');
-- RESULT: supplier EXACT_ID -> S042; part EXACT_NAME -> P104; plant EXACT_NAME -> P01. PASS

-- Bonus: graceful all-null-input handling
CALL SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(NULL, NULL, NULL);
-- RESULT: {"REASON": "No entity references were supplied. Provide at least one of
--          supplier_reference, part_reference, or plant_reference."}  -- no error. PASS

/* ===========================================================================
   SECTION C : AGENT END-TO-END TESTS (8/8 PASS)
   Verified via SNOWFLAKE.CORTEX.DATA_AGENT_RUN, inspecting the full JSON
   trace (tool_use / tool_result blocks), not just final answer text.
   =========================================================================== */

-- Test A: flagship natural-language question
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries? Compare the options and recommend the best intervention."}]}]}'
) AS RESPONSE;
-- TRACE: resolve_supply_chain_entities called first -> all 3 EXACT_NAME (S017/P104/P01) ->
--        evaluate_supply_chain_interventions('S017','P104','P01') called ->
--        shortage 2150, EXPEDITED_REPLENISHMENT rank1/recommended (Road 3d, arrives 2026-08-18),
--        INTERPLANT_TRANSFER rank2 (P03), ALTERNATE_SUPPLIER rank3 (S042, 926650 INR),
--        EXPEDITE_CURRENT_SHIPMENT rank4/not feasible (SH900001).
--        Final answer opens with "Resolved Pinnacle Industries (S017)..." and includes the
--        Phase 7B governance-patch operational-Road-vs-contractual-Air distinction. PASS

-- Test B: canonical-ID flagship (parity baseline)
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the S017 P104 shortage at P01? What do you recommend and why?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver NOT called (clean canonical IDs) -> evaluate_supply_chain_interventions directly
--        with S017/P104/P01 -> identical values to Test A. Confirms natural-language vs
--        canonical-ID parity. PASS

-- Test C: unique-partial flagship question
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the Hydraulic Control Valve shortage at Pune, given Pinnacle Ind is the supplier?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> all 3 UNIQUE_MATCH (S017/P104/P01) -> intervention tool called ->
--        same result values as Test A/B. PASS

-- Test D: mixed ID + names
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Can S042 cover the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> supplier EXACT_ID (S042), part/plant EXACT_NAME (P104/P01) ->
--        evaluate_supply_chain_interventions('S042','P104','P01') called. PASS

-- Test E: ambiguous supplier - intervention tool must NOT be called
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Can Pinnacle cover the P104 shortage at Pune Assembly Plant?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> supplier AMBIGUOUS (4 candidates S017/S042/S067/S092) ->
--        evaluate_supply_chain_interventions NOT called -> Agent lists candidates and asks
--        the user to choose. PASS

-- Test F: ambiguous exact-text duplicate part description - intervention tool must NOT be called
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"Can S017 supply the Seal Kit Type 318 part shortage at P01?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> supplier/plant resolved (EXACT_ID); part AMBIGUOUS (P086/P986) ->
--        evaluate_supply_chain_interventions NOT called -> Agent asks which part ID (P086 or P986). PASS

-- Test G: fuzzy supplier typo - intervention tool must NOT be called without confirmation
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the P104 shortage at P01 caused by Pinacle Industries?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> part/plant EXACT_ID; supplier FUZZY_CANDIDATES (top S017, score 94) ->
--        evaluate_supply_chain_interventions NOT called -> Agent asks "Did you mean S017 - Pinnacle
--        Industries?" and waits for confirmation. PASS

-- Test H: no-match entity - intervention tool must NOT be called
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What can we do about the shortage caused by Quantum Robotics Unlimited for part P104 at Pune Assembly Plant?"}]}]}'
) AS RESPONSE;
-- TRACE: resolver called -> part/plant resolved; supplier NO_MATCH ->
--        evaluate_supply_chain_interventions NOT called -> Agent explains supplier could not be
--        identified and asks for canonical ID or more exact name. PASS

/* ===========================================================================
   SECTION D : PHASE 6/7 REGRESSION (all PASS, unchanged)
   =========================================================================== */

-- D1: pure analytics question - resolver must NOT be called
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is our overall supplier on-time delivery rate?"}]}]}'
) AS RESPONSE;
-- RESULT: 0.751929 (75.2%) via supply_chain_analytics only, resolver not invoked. Matches
--         governed baseline exactly. PASS

-- D2: S017 OTD + SLA penalty terms (hybrid regression)
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is supplier S017 on-time delivery rate, and what penalty terms exist in their SLA?"}]}]}'
) AS RESPONSE;
-- RESULT: S017 OTD = 0.493506 (49.4%), matches governed baseline; SLA penalty terms correctly
--         cited from DOC000217 (2% per week of delay, capped at 10%). PASS

-- D3: warranty negative control - no-hallucination test
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What is the warranty period for supplier S017?"}]}]}'
) AS RESPONSE;
-- RESULT: correctly states no warranty clause found in any of S017's 4 documents. No
--         hallucination. PASS

-- D4: canonical-ID flagship intervention recommendation + operational-vs-contractual governance
-- (see Test B above - reproduces Phase 7B governance-patch behavior identically). PASS

/* ===========================================================================
   SECTION E : PHASE 1-5 / STRUCTURAL REGRESSION
   =========================================================================== */

-- E1: Semantic View structure unchanged
DESCRIBE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW;
SELECT "object_kind", COUNT(DISTINCT "object_name") AS DISTINCT_OBJECTS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "object_kind" IN ('TABLE','RELATIONSHIP','FACT','METRIC','AI_VERIFIED_QUERY')
GROUP BY 1 ORDER BY 1;
-- RESULT: TABLE=12, RELATIONSHIP=15, FACT=26, METRIC=32, AI_VERIFIED_QUERY=15. Unchanged. PASS

-- E2: Cortex Search Service unchanged
SHOW CORTEX SEARCH SERVICES LIKE 'SUPPLIER_DOCUMENT_SEARCH' IN SCHEMA SUPPLYCHAINIQ_DB.SEARCH;
-- RESULT: indexing_state=ACTIVE, serving_state=ACTIVE, source_data_num_rows=139. Unchanged. PASS

-- E3: 14 CURATED views unchanged
SHOW VIEWS IN SCHEMA SUPPLYCHAINIQ_DB.CURATED;
-- RESULT: 14 views (CARRIER, CUSTOMER, CUSTOMER_ORDER_LINE, DEMAND, INTERPLANT_TRANSFER_OPTION,
--         INVENTORY_SNAPSHOT, PART, PLANT, PURCHASE_ORDER_LINE, SHIPMENT, SUPPLIER, SUPPLIER_PART,
--         SUPPLIER_PERFORMANCE, TRANSPORT_OPTION). Unchanged. PASS

-- E4: EVALUATE_SUPPLY_CHAIN_INTERVENTIONS calculations/ranking unchanged - confirmed by Test B
-- reproducing identical values (shortage 2150, same 4-option ranking) to the pre-Phase-8A baseline.
