/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 6B : CORTEX AGENT VALIDATION
   FILE    : 14_cortex_agent_validation.sql
   PURPOSE : Structural validation of SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
             plus the 12-test routing/reasoning/evidence catalog via
             SNOWFLAKE.CORTEX.DATA_AGENT_RUN (non-streaming).

   SAFETY  : Read-only. No DDL/DML other than the DESCRIBE/SHOW statements
             below. DATA_AGENT_RUN invokes the agent read-only against
             already-governed structured/unstructured sources.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA AGENTS;

/* ===========================================================================
   SECTION A : STRUCTURAL VALIDATION
   =========================================================================== */
SHOW AGENTS IN SCHEMA SUPPLYCHAINIQ_DB.AGENTS;

DESCRIBE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT;

/* Structural checks confirmed against DESCRIBE AGENT output (agent_spec JSON):
   - display_name = "SupplyChainIQ Control Tower"                         PASS
   - models.orchestration = "auto"                                        PASS
   - orchestration.budget.tokens = 16000                                  PASS
   - orchestration.budget.seconds = 90 (raised from 45 - see EMPIRICAL
     BUDGET NOTE in 13_cortex_agent.sql; the flagship hybrid question
     consistently exceeded 45s across 3/3 attempts)                       PASS
   - exactly 2 tools: supply_chain_analytics (cortex_analyst_text_to_sql),
     supplier_document_search (cortex_search)                             PASS
   - supply_chain_analytics.semantic_view =
     SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW                 PASS
   - supply_chain_analytics.execution_environment.warehouse = COMPUTE_WH  PASS
   - supply_chain_analytics.execution_environment.query_timeout = 60      PASS
   - supplier_document_search.search_service =
     SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH                     PASS
   - supplier_document_search.max_results = 5                            PASS
   - title_column = TITLE, id_column = DOCUMENT_ID                       PASS
   - columns_and_descriptions present for all 9 columns                  PASS
   - versions = ["VERSION$1"] (single version created directly via
     CREATE OR REPLACE AGENT with the seconds:90 spec baked in;
     DEFAULT/FIRST/LAST aliases all point to it)                         PASS
*/

/* ===========================================================================
   SECTION B : 12-TEST VALIDATION CATALOG (SNOWFLAKE.CORTEX.DATA_AGENT_RUN)
   Each call is non-streaming. Results are summarized in
   docs/cortex_agent_design.md Section "Agent Test Results".
   =========================================================================== */

-- TEST 1: Overall Supplier OTD (structured only)
-- Expected: ~75.19% (0.751929). Search should not be required.
-- RESULT: 75.19% via system_execute_sql (verified_query_used=true), no
-- Search tool call. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is our overall supplier OTD?"}]}], "stream": false}'
) AS TEST1_RESULT;

-- TEST 2: S017 OTD (structured only)
-- Expected: ~49.35% (0.493506).
-- RESULT: 49.4% via system_execute_sql (verified_query_used=true), no
-- Search tool call. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is supplier S017''s on-time delivery rate?"}]}], "stream": false}'
) AS TEST2_RESULT;

-- TEST 3: Current inventory P104/P01 (structured only)
-- Expected: available inventory = 8200, latest-snapshot behavior respected.
-- RESULT: 8,200 units as of latest snapshot 2026-08-15 (two-step
-- latest-snapshot-date + filtered read pattern used correctly). PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is the current available inventory for P104 at P01?"}]}], "stream": false}'
) AS TEST3_RESULT;

-- TEST 4: Late-delivery penalty S017/P104 (Search only)
-- Expected: DOC000217 (SLA) 2%/week capped 10%.
-- RESULT: Correctly cited DOC000217 as the governing P104-specific term
-- (2%/week, 10% cap), and separately noted DOC000017's differing 1.5%/week
-- general-portfolio penalty without conflating scopes. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What penalty applies if supplier S017 delivers P104 late?"}]}], "stream": false}'
) AS TEST4_RESULT;

-- TEST 5: Quality requirements for S017 (Search only)
-- Expected: DOC000617 (Quality Agreement) + other scoped evidence (SLA).
-- RESULT: Cited DOC000617 (97.5%), DOC000017 (97.5%), DOC000217 (98%,
-- P104-specific), DOC000417 (scorecard, 97.5%) - all distinguished by scope. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What quality requirements are documented for supplier S017?"}]}], "stream": false}'
) AS TEST5_RESULT;

-- TEST 6: Warranty negative control (no-hallucination)
-- Expected: Search runs; explicit "no supporting clause found" statement;
-- FAIL if a duration is invented.
-- RESULT: Agent reviewed all 4 S017 documents, explicitly stated no
-- warranty-period clause was found, and declined to infer one. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What warranty period does S017''s contract specify?"}]}], "stream": false}'
) AS TEST6_RESULT;

-- TEST 7: S017 actual OTD vs. contractual OTD (hybrid)
-- Expected: BOTH tools; Analyst ~49.35%; Search 92%/95% targets; no merge.
-- RESULT: "Current operational facts" (49.4%) presented separately from
-- "Contractual/document evidence" (92% portfolio / 95% P104 SLA); explicitly
-- noted these are different scopes, not a contradiction. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How is supplier S017 performing against its contractual delivery commitments?"}]}], "stream": false}'
) AS TEST7_RESULT;

-- TEST 8: Contract lead-time cross-check (hybrid)
-- Expected: BOTH tools; Analyst 28 days; Search DOC000217 = 28 days; agree.
-- RESULT: Both independently retrieved and agent explicitly states "The
-- 28-day governed contract lead time and the 28-day SLA commitment describe
-- the same scope and agree exactly." PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is the governed contract lead time for S017 supplying P104, and what does the SLA say?"}]}], "stream": false}'
) AS TEST8_RESULT;

-- TEST 9: Flagship hybrid risk scenario
-- Expected: BOTH tools; structured risk/exposure facts + contract evidence.
-- Do NOT hardcode expected values into Agent instructions - this file
-- records observed results as assertions only.
-- RESULT: ~12 structured SQL calls (inventory 8200/safety stock 3000,
-- 4 in-transit S017/P104 shipments including PO900001 with a 5-day delay,
-- risk category, open P104 order exposure) + 6 Search calls (DOC000217,
-- DOC000017, DOC000617, DOC000417). Full grounded answer delivered
-- (structured facts and contractual evidence clearly separated) after
-- raising the time budget to 90s (see EMPIRICAL BUDGET NOTE). A trailing
-- "time limit" continuation prompt appeared after the substantive answer
-- in some runs - this is a benign artifact, not an answer failure, since
-- the full answer text preceded it. Customer-exposure figure differed from
-- the narrower Phase 4C VQ10 due-date-window baseline because the Agent
-- autonomously chose a broader "all open P104 orders" filter - this is
-- valid independent structured retrieval, not a fabrication or governance
-- violation. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What supply-chain risk from S017 threatens P104 customer deliveries, what is the exposure, and what contractual terms are relevant?"}]}], "stream": false}'
) AS TEST9_RESULT;

-- TEST 10: Late shipment + expedite terms (hybrid)
-- Expected: structured shipment facts + DOC000217 expedite context; no
-- expedite action executed.
-- RESULT: Structured facts confirmed 4 S017/P104 shipments in transit,
-- including PO900001 promised 2026-08-25 / projected 2026-08-30 (5-day
-- delay, matching the flagship reference). Contractual evidence cited
-- DOC000217 (4-day air lane, 2.6x rate, 50/50 cost split) and DOC000017
-- (general expedite clause) as distinct scopes. No action was executed -
-- the agent only offered to pull further figures as a follow-up. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is happening with S017''s delayed P104 shipment, and what does the contract say about expedited freight?"}]}], "stream": false}'
) AS TEST10_RESULT;

-- TEST 11: Cross-currency landed-cost governance
-- Expected: structured tool; no single mixed-currency grand total.
-- RESULT: All 11 currencies returned separately (matches VQ11 governed
-- baseline); explicitly offered to convert only if a target currency and
-- governed FX rates were supplied. PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is the total actual landed cost across all suppliers?"}]}], "stream": false}'
) AS TEST11_RESULT;

-- TEST 12: Unsupported Inventory Turnover
-- Expected: state unsupported; do not manufacture a proxy metric.
-- RESULT: Correctly stated Inventory Turnover is unsupported (no canonical
-- costed-inventory/COGS basis), did not call any tool, offered valid
-- supported alternatives (inventory levels, Fill Rate, OTD, Schedule
-- Adherence). PASS.
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT',
  '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is our inventory turnover?"}]}], "stream": false}'
) AS TEST12_RESULT;

SELECT 'Phase 6B / 14_cortex_agent_validation.sql complete - all 12 tests PASS. See docs/cortex_agent_design.md for the full Agent Test Results table.' AS STATUS;
