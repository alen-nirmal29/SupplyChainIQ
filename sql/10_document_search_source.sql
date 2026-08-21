/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 5B : CORTEX SEARCH - SOURCE AUDIT + SEARCH SCHEMA
   FILE    : 10_document_search_source.sql
   PURPOSE : Reconfirm the real SUPPLIER_DOCUMENTS source table (row count,
             uniqueness, nulls, retention/change-tracking state) and create
             the SUPPLYCHAINIQ_DB.SEARCH schema (only if absent) that will
             host the Cortex Search Service. No chunk table, no derived
             search table, and no duplication of CONTENT is created here -
             the SEARCH_TEXT projection is computed inline inside the Cortex
             Search service's own AS query (see 11_cortex_search_service.sql).

   SAFETY  : Read-only against SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS.
             The only DDL in this file is CREATE SCHEMA IF NOT EXISTS SEARCH.
             No document rows are modified. No existing schema is altered.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : SOURCE TABLE RECONFIRMATION (not relying on Phase 5A memory)
   =========================================================================== */

SELECT 'A1. Row count = 139' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS) = 139, 'PASS', 'FAIL') AS RESULT
UNION ALL
SELECT 'A2. DOCUMENT_ID non-null for all rows',
       IFF((SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS WHERE DOCUMENT_ID IS NULL) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'A3. COUNT(DISTINCT DOCUMENT_ID) = 139 (unique primary-key candidate)',
       IFF((SELECT COUNT(DISTINCT DOCUMENT_ID) FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS) = 139, 'PASS', 'FAIL')
UNION ALL
SELECT 'A4. CONTENT null count = 0',
       IFF((SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS WHERE CONTENT IS NULL) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'A5. Expected 9-column schema present (DOCUMENT_ID, SUPPLIER_ID, DOCUMENT_TYPE, TITLE, EFFECTIVE_DATE, EXPIRY_DATE, CONTENT, SOURCE_REFERENCE, CREATED_AT)',
       IFF(
         (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = 'DOCUMENTS' AND TABLE_NAME = 'SUPPLIER_DOCUMENTS'
             AND COLUMN_NAME IN ('DOCUMENT_ID','SUPPLIER_ID','DOCUMENT_TYPE','TITLE','EFFECTIVE_DATE','EXPIRY_DATE','CONTENT','SOURCE_REFERENCE','CREATED_AT')) = 9,
       'PASS', 'FAIL');

-- A6. Max content length sanity check (whole-document indexing rationale)
SELECT 'A6. Max CONTENT length' AS CHECK_NAME, MAX(LENGTH(CONTENT)) AS MAX_LEN,
       IFF(MAX(LENGTH(CONTENT)) < 8000, 'PASS (well under any single-pass embedding limit)', 'REVIEW') AS RESULT
FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS;

/* ===========================================================================
   SECTION B : RETENTION / CHANGE-TRACKING STATE (recorded BEFORE Search
   Service creation - Cortex Search incremental refresh requires change
   tracking on the underlying source; if Snowflake enables it automatically
   during service creation, that is recorded in 11_cortex_search_service.sql
   and in docs/cortex_search_design.md - it is NOT silently omitted here).
   =========================================================================== */

SHOW TABLES LIKE 'SUPPLIER_DOCUMENTS' IN SCHEMA SUPPLYCHAINIQ_DB.DOCUMENTS;
SELECT '"retention_time"' AS METRIC, "retention_time" AS VALUE FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
UNION ALL
SELECT '"change_tracking"', "change_tracking" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

/* ===========================================================================
   SECTION C : CREATE SEARCH SCHEMA (only if absent - verified via SHOW SCHEMAS
   in Phase 5A: SUPPLYCHAINIQ_DB.SEARCH did not exist prior to this file).
   =========================================================================== */

CREATE SCHEMA IF NOT EXISTS SUPPLYCHAINIQ_DB.SEARCH
  COMMENT = 'Phase 5: Cortex Search layer for unstructured supplier-document retrieval. Structured analytics remain exclusively in SUPPLYCHAINIQ_DB.SEMANTIC.';

-- C1. Confirm schema now exists and no other schema was touched
SHOW SCHEMAS IN DATABASE SUPPLYCHAINIQ_DB;
SELECT 'C1. SEARCH schema exists' AS CHECK_NAME,
       IFF((SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = 'SEARCH') = 1, 'PASS', 'FAIL') AS RESULT;

/* ===========================================================================
   NOTE: No chunk table, no derived SEARCH-schema table, and no copy of
   CONTENT is created in this file. Whole-document indexing is used
   (max content length ~3037 characters, well under any single embedding
   pass). The SEARCH_TEXT column is computed inline inside the Cortex
   Search Service's own source query in 11_cortex_search_service.sql -
   it does not exist as a materialized column or table anywhere.
   =========================================================================== */

SELECT 'Phase 5B / 10_document_search_source.sql complete - proceed to 11_cortex_search_service.sql' AS STATUS;
