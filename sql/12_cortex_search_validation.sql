/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 5B : CORTEX SEARCH SERVICE VALIDATION
   FILE    : 12_cortex_search_validation.sql
   PURPOSE : Structural validation of SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH
             plus the 10-test retrieval catalog (SEARCH_PREVIEW), a date-range
             attribute filter test, and a primary-key lookup finding.

   SAFETY  : Read-only. No DDL/DML. SEARCH_PREVIEW is a read-only development/
             testing interface, not the final Agent serving path.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA SEARCH;

/* ===========================================================================
   SECTION A : STRUCTURAL SERVICE VALIDATION
   =========================================================================== */
DESCRIBE CORTEX SEARCH SERVICE SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH;

SELECT 'A1. search_column = SEARCH_TEXT' AS CHECK_NAME,
       IFF((SELECT "search_column" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'SEARCH_TEXT', 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'A2. primary_key_columns = DOCUMENT_ID',
       IFF((SELECT "primary_key_columns" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'DOCUMENT_ID', 'PASS', 'FAIL')
UNION ALL
SELECT 'A3. attribute_columns include SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE',
       IFF((SELECT "attribute_columns" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'SUPPLIER_ID,DOCUMENT_TYPE,EFFECTIVE_DATE,EXPIRY_DATE', 'PASS', 'FAIL')
UNION ALL
SELECT 'A4. warehouse = COMPUTE_WH',
       IFF((SELECT "warehouse" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'COMPUTE_WH', 'PASS', 'FAIL')
UNION ALL
SELECT 'A5. target_lag = 12 hours',
       IFF((SELECT "target_lag" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = '12 hours', 'PASS', 'FAIL')
UNION ALL
SELECT 'A6. source_data_num_rows = 139',
       IFF((SELECT "source_data_num_rows" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 139, 'PASS', 'FAIL')
UNION ALL
SELECT 'A7. indexing_state = ACTIVE',
       IFF((SELECT "indexing_state" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'ACTIVE', 'PASS', 'FAIL')
UNION ALL
SELECT 'A8. serving_state = ACTIVE',
       IFF((SELECT "serving_state" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'ACTIVE', 'PASS', 'FAIL')
UNION ALL
SELECT 'A9. indexing_error is empty (healthy, no error)',
       IFF(COALESCE((SELECT "indexing_error" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))), '') = '', 'PASS', 'FAIL')
UNION ALL
SELECT 'A10. auto_suspend is NULL (not set, per Phase 5 baseline)',
       IFF((SELECT "auto_suspend" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) IS NULL, 'PASS', 'FAIL')
UNION ALL
SELECT 'A11. refresh_mode = INCREMENTAL',
       IFF((SELECT "refresh_mode" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) = 'INCREMENTAL', 'PASS', 'FAIL');

-- A12. Record actual embedding model selected by Snowflake
SELECT 'A12. Embedding model actually selected' AS NOTE, "embedding_model" AS EMBEDDING_MODEL
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)));

/* ===========================================================================
   SECTION B : RETRIEVAL TEST CATALOG (SEARCH_PREVIEW)
   Each test is executed individually below; results are recorded in
   docs/cortex_search_design.md Section "Document Retrieval Quality Summary".
   =========================================================================== */

-- TEST 1: S017 SLA lookup (filter SUPPLIER_ID='S017')
-- Expected: DOC000217 top-ranked; contains 28-day / 95% OTD / 98% quality.
-- RESULT: DOC000217 ranked #1 (reranker_score 1.789, highest). PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What SLA commitments exist for supplier S017?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST1_RESULT;

-- TEST 2: lead-time nuance (filter SUPPLIER_ID='S017')
-- Expected: both DOC000017 (22-day, portfolio) and DOC000217 (28-day, P104 SLA) retrievable.
-- RESULT: both returned in top 2 of 4. Distinction preserved (not treated as contradiction). PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What contractual lead-time obligation is documented for S017?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST2_RESULT;

-- TEST 3: delivery performance percentage (filter SUPPLIER_ID='S017')
-- Expected: 92% (general contract) and 95% (P104 SLA) both retrievable evidence.
-- RESULT: all 4 S017 docs returned (DOC000017, DOC000417, DOC000617, DOC000217); both percentages present. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What delivery performance percentage must S017 maintain?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST3_RESULT;

-- TEST 4: quality acceptance rate (filter SUPPLIER_ID='S017')
-- Expected: Quality Agreement (97.5%) and SLA (98%) both retrievable.
-- RESULT: DOC000617 ranked #1, DOC000217 (98%) present in top 4. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What quality acceptance rate is required from S017?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST4_RESULT;

-- TEST 5: penalty for late delivery (filter SUPPLIER_ID='S017')
-- Expected: DOC000217 (2%/week capped 10%) and/or DOC000017 (1.5%/week) rank strongly.
-- RESULT: DOC000217 rank #1, DOC000017 rank #2 of 4. Both in top 5. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What penalty applies if S017 delivers late?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST5_RESULT;

-- TEST 6: attribute supplier filter isolation (filter SUPPLIER_ID='S042')
-- Expected: every returned row SUPPLIER_ID = S042, no S017 leakage.
-- RESULT: 4 rows returned, all SUPPLIER_ID = S042 (DOC000042/242/442/642). PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "supplier contract terms",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S042"}},
       "limit": 10
     }'
  )
):results AS TEST6_RESULT;

-- TEST 7: document-type filter (filter DOCUMENT_TYPE='Logistics Policy')
-- Expected: DOC000904, DOC000905 only; SUPPLIER_ID may legitimately be NULL.
-- RESULT: exactly 2 rows returned, both DOCUMENT_TYPE = Logistics Policy, SUPPLIER_ID null. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "logistics expedite mode selection policy",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"DOCUMENT_TYPE": "Logistics Policy"}},
       "limit": 10
     }'
  )
):results AS TEST7_RESULT;

-- TEST 8: keyword-heavy query (filter SUPPLIER_ID='S017')
-- Expected: DOC000217 ranks highly.
-- RESULT: DOC000217 rank #2 of 4 by blended score, but has the dominant text_match
-- score (0.052 vs ~3e-7 for others) - the literal phrase match is concentrated there. PASS (top-2, strong text-match).
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "escalation twenty-four hours Supply Continuity Council",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST8_RESULT;

-- TEST 9: semantic/paraphrased query (no filter)
-- Expected: DOC000217 appears within top relevant results without exact keyword match.
-- RESULT: DOC000217 ranked #1 of 5. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "If Pinnacle Industries ships late for the hydraulic valve part, what happens?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "limit": 5
     }'
  )
):results AS TEST9_RESULT;

-- TEST 10: negative control (filter SUPPLIER_ID='S017')
-- Expected: retrieval still returns ranked documents (Cortex Search does not
-- refuse to return results), but NONE of the returned CONTENT actually
-- contains a warranty clause / warranty period.
-- RESULT: 4 S017 docs returned; verified none contain the string "warranty"
-- (case-insensitive) anywhere in CONTENT. Recorded as "no supporting
-- evidence found in returned corpus" - this is the correct negative-control
-- behavior, not a search failure. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "What warranty period does S017'' s contract specify?",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE","EFFECTIVE_DATE","EXPIRY_DATE","SOURCE_REFERENCE","CONTENT"],
       "filter": {"@eq": {"SUPPLIER_ID": "S017"}},
       "limit": 5
     }'
  )
):results AS TEST10_RESULT;

-- Programmatic negative-control assertion: none of the S017 CONTENT contains "warranty"
SELECT 'TEST10 assertion: zero warranty mentions across all S017 documents' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS
             WHERE SUPPLIER_ID = 'S017' AND CONTENT ILIKE '%warranty%') = 0, 'PASS', 'FAIL') AS RESULT;

/* ===========================================================================
   SECTION C : DATE ATTRIBUTE FILTER TEST (structural, @gte/@lte)
   =========================================================================== */
-- Expected: all returned rows have EFFECTIVE_DATE between 2025-09-01 and 2025-09-30.
-- RESULT: 10 rows returned, all EFFECTIVE_DATE within range (confirmed 2025-09-02
-- through 2025-09-30). Date-range filtering confirmed supported. PASS.
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "supplier agreement",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","EFFECTIVE_DATE"],
       "filter": {"@and": [{"@gte": {"EFFECTIVE_DATE": "2025-09-01"}}, {"@lte": {"EFFECTIVE_DATE": "2025-09-30"}}]},
       "limit": 10
     }'
  )
):results AS DATE_FILTER_RESULT;

/* ===========================================================================
   SECTION D : PRIMARY-KEY LOOKUP FINDING
   IMPORTANT FINDING (documented, not worked around): DOCUMENT_ID is declared
   as PRIMARY KEY on the service but was NOT also declared in ATTRIBUTES.
   In this account's deployed Cortex Search version, PRIMARY KEY columns
   govern document identity / incremental-refresh change detection - they
   are NOT automatically usable as an @eq filter predicate unless the same
   column is also listed in ATTRIBUTES. Attempting to filter on DOCUMENT_ID
   directly fails with error 399114 ("Invalid filter query: Column
   DOCUMENT_ID does not exist as a filter"). This is reported as a real
   constraint of the current design (matches the approved ATTRIBUTES list:
   SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE - DOCUMENT_ID was
   intentionally not included there). A compound-attribute filter
   (SUPPLIER_ID + DOCUMENT_TYPE) is demonstrated below as the practical
   PK-equivalent lookup path given the current declared ATTRIBUTES.
   =========================================================================== */

-- D1. Direct DOCUMENT_ID @eq filter (EXPECTED TO FAIL - documented finding, not a bug to silently fix)
-- Uncomment to reproduce: fails with error 399114.
-- SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
--   'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
--   '{"query": "SLA", "columns": ["DOCUMENT_ID"], "filter": {"@eq": {"DOCUMENT_ID": "DOC000217"}}, "limit": 5}'
-- );

-- D2. Practical PK-equivalent lookup via compound declared-attribute filter
-- Expected: exactly DOC000217 returned.
-- RESULT: exactly 1 row, DOCUMENT_ID = DOC000217. PASS (PK-equivalent path).
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH',
    '{
       "query": "Service Level Agreement Pinnacle Industries S017 hydraulic control valve P104",
       "columns": ["DOCUMENT_ID","SUPPLIER_ID","DOCUMENT_TYPE","TITLE"],
       "filter": {"@and": [{"@eq": {"SUPPLIER_ID": "S017"}}, {"@eq": {"DOCUMENT_TYPE": "SLA"}}]},
       "limit": 3
     }'
  )
):results AS PK_EQUIVALENT_RESULT;

SELECT 'Phase 5B / 12_cortex_search_validation.sql complete - see docs/cortex_search_design.md for the full Document Retrieval Quality Summary table' AS STATUS;
