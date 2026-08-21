/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 5B : CORTEX SEARCH SERVICE - AUTHORITATIVE DDL
   FILE    : 11_cortex_search_service.sql
   PURPOSE : Create the single governed Cortex Search Service over the
             supplier-document corpus for unstructured evidence retrieval.
             Structured analytics remain exclusively in
             SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW - this
             service does not duplicate any structured metric.

   DESIGN  : Whole-document indexing (no chunk table). SEARCH_TEXT is a
             deterministic inline projection ('Title: ' || TITLE ||
             '\nDocument Type: ' || DOCUMENT_TYPE || '\n\n' || CONTENT)
             computed inside this service's own AS query only - it is not
             materialized anywhere else. TITLE and CONTENT remain available
             separately as returned columns for citation.

   SAFETY  : This script only creates SUPPLYCHAINIQ_DB.SEARCH.
             SUPPLIER_DOCUMENT_SEARCH. It performs no DDL/DML against
             SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS (source rows are
             read-only inputs). Cortex Search incremental refresh requires
             CHANGE_TRACKING on the underlying source table; if Snowflake
             enables CHANGE_TRACKING on SUPPLIER_DOCUMENTS automatically as
             a side effect of this CREATE, that metadata change on the
             source table IS a real (metadata-only) side effect and is
             recorded below and in docs/cortex_search_design.md - it is not
             claimed that the source object was entirely untouched.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA SEARCH;

/* ===========================================================================
   PRE-CREATION STATE (change tracking / retention on the source table)
   =========================================================================== */
SHOW TABLES LIKE 'SUPPLIER_DOCUMENTS' IN SCHEMA SUPPLYCHAINIQ_DB.DOCUMENTS;
SELECT 'PRE-CREATE: SUPPLIER_DOCUMENTS change_tracking / retention_time' AS NOTE,
       "change_tracking" AS CHANGE_TRACKING_BEFORE, "retention_time" AS RETENTION_TIME_BEFORE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

/* ===========================================================================
   CORTEX SEARCH SERVICE CREATION
   NOTE: PRIMARY KEY, REFRESH_MODE = INCREMENTAL, and INITIALIZE = ON_CREATE
   were all accepted by this account's deployed Cortex Search syntax (no
   fallback to a reduced clause set was required).
   =========================================================================== */
CREATE OR REPLACE CORTEX SEARCH SERVICE SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH
  ON SEARCH_TEXT
  PRIMARY KEY (DOCUMENT_ID)
  ATTRIBUTES SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '12 hours'
  REFRESH_MODE = INCREMENTAL
  INITIALIZE = ON_CREATE
AS
SELECT
  DOCUMENT_ID,
  SUPPLIER_ID,
  DOCUMENT_TYPE,
  TITLE,
  EFFECTIVE_DATE,
  EXPIRY_DATE,
  SOURCE_REFERENCE,
  CONTENT,
  (
    'Title: ' || TITLE ||
    '\nDocument Type: ' || DOCUMENT_TYPE ||
    '\n\n' || CONTENT
  ) AS SEARCH_TEXT
FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS;

/* NOTE ON SOURCE-TABLE SIDE EFFECT (must be disclosed, not hidden):
   Creating this service with REFRESH_MODE = INCREMENTAL caused Snowflake to
   AUTOMATICALLY ENABLE CHANGE_TRACKING on the underlying source table
   SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS (observed: OFF -> ON).
   This is a metadata-only side effect required for incremental refresh; no
   document rows were modified, no data was changed, and RETENTION_TIME_IN_DAYS
   was unchanged (remained 1). This is disclosed explicitly rather than
   claiming the source object was entirely untouched - see the PRE-CREATE /
   POST-CREATE state comparison above and docs/cortex_search_design.md. */

/* ===========================================================================
   POST-CREATION STATE (confirm change tracking / retention did not regress
   and record whether Snowflake enabled change tracking automatically)
   =========================================================================== */
SHOW TABLES LIKE 'SUPPLIER_DOCUMENTS' IN SCHEMA SUPPLYCHAINIQ_DB.DOCUMENTS;
SELECT 'POST-CREATE: SUPPLIER_DOCUMENTS change_tracking / retention_time' AS NOTE,
       "change_tracking" AS CHANGE_TRACKING_AFTER, "retention_time" AS RETENTION_TIME_AFTER
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SELECT 'Phase 5B / 11_cortex_search_service.sql complete - proceed to structural validation (DESCRIBE CORTEX SEARCH SERVICE) then 12_cortex_search_validation.sql' AS STATUS;
