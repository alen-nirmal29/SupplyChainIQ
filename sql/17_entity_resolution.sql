/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 8A.2 : NATURAL-LANGUAGE ENTITY RESOLUTION - AUTHORITATIVE DDL
   FILE    : 17_entity_resolution.sql
   PURPOSE : Create the deterministic, read-only entity resolver and attach
             it as a FOURTH custom tool to the existing
             SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT. Read-only: no
             writes, no aliasing, no automatic decisions - only converts
             supplier/part/plant business references into governed
             canonical IDs, or reports AMBIGUOUS / FUZZY_CANDIDATES /
             NO_MATCH so the Agent never guesses.

   SAFETY  : Read-only SELECT-only procedure body (EXECUTE AS CALLER) over
             SUPPLYCHAINIQ_DB.CURATED.SUPPLIER / PART / PLANT. Redeploys the
             existing Agent via CREATE OR REPLACE AGENT with the FULL
             preserved Phase 7B specification plus the new tool - the first
             three tools, budgets, and resources are reproduced verbatim,
             only extended, never removed.

   EMPIRICAL INTEGRATION FIX (discovered via live testing in Phase 8A,
   documented rather than silently worked around):
   Snowflake does NOT guarantee lazy/short-circuit evaluation of correlated
   scalar subqueries inside CASE WHEN branches for this procedure body. A
   branch such as "WHEN C2 = 1 THEN ... (SELECT SUPPLIER_ID FROM tier2) ..."
   raised "Single-row subquery returns more than one row" even when C2 = 2
   and that branch was NOT the one logically selected, because the engine
   evaluates/plans the subquery regardless of which CASE branch is chosen.
   Fixed by rewriting every such scalar reference as an aggregate
   (e.g. "(SELECT MAX(SUPPLIER_ID) FROM tier2)"), which always returns
   exactly one row/value no matter how many rows the underlying tier CTE
   has, eliminating the error while leaving resolution semantics unchanged
   (the aggregate value is only ever read when its branch is genuinely
   selected, i.e. when the tier has exactly one row).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA DECISION;

/* ===========================================================================
   SECTION A : RESOLVER PROCEDURE
   Reads only from CURATED.SUPPLIER / PART / PLANT. No writes of any kind.
   Deterministic tiered ladder per entity type (independent):
     TIER 1 EXACT_ID -> TIER 2 EXACT_NAME -> TIER 3 NORMALIZED_EXACT ->
     TIER 4 UNIQUE_MATCH (partial) -> TIER 5 FUZZY_CANDIDATES -> NO_MATCH.
   Mandatory distinct-canonical-ID rule: a tier only auto-resolves when
   exactly one distinct canonical ID matches; 2+ distinct IDs at any tier
   (including EXACT tiers) => AMBIGUOUS, never "first row wins". Verified
   empirically: "Seal Kit Type 318" is an EXACT textual match to both P086
   and P986 and correctly returns AMBIGUOUS.
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(
  SUPPLIER_REFERENCE VARCHAR,
  PART_REFERENCE VARCHAR,
  PLANT_REFERENCE VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8A: deterministic, read-only entity resolver. Converts supplier/part/plant business references (canonical ID, exact name, normalized name, unique partial name, or fuzzy typo) into governed canonical IDs from CURATED.SUPPLIER/PART/PLANT. Never auto-resolves when multiple distinct canonical IDs match (AMBIGUOUS) or when only fuzzy similarity exists (FUZZY_CANDIDATES) - both leave CANONICAL_ID NULL. Read-only: SELECT only, no writes.'
EXECUTE AS CALLER
AS
$$
DECLARE
  supplier_result VARIANT DEFAULT NULL;
  part_result VARIANT DEFAULT NULL;
  plant_result VARIANT DEFAULT NULL;
  final_result VARIANT;
BEGIN

  IF (:SUPPLIER_REFERENCE IS NOT NULL AND TRIM(:SUPPLIER_REFERENCE) <> '') THEN
    supplier_result := (
      WITH ref AS (SELECT TRIM(:SUPPLIER_REFERENCE) AS RAW_REF),
      base AS (
        SELECT SUPPLIER_ID, SUPPLIER_NAME, SUPPLIER_NAME_PORTAL, REGION, VENDOR_STATUS,
               UPPER(SUPPLIER_NAME) AS NAME_U, UPPER(SUPPLIER_NAME_PORTAL) AS PORTAL_U,
               UPPER(REGEXP_REPLACE(TRIM(SUPPLIER_NAME), '[[:space:]]+', ' ')) AS NAME_N,
               UPPER(REGEXP_REPLACE(TRIM(SUPPLIER_NAME_PORTAL), '[[:space:]]+', ' ')) AS PORTAL_N
        FROM SUPPLYCHAINIQ_DB.CURATED.SUPPLIER
      ),
      tier1 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.SUPPLIER_ID),
      tier2 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.NAME_U OR UPPER(ref.RAW_REF) = b.PORTAL_U),
      tier3 AS (SELECT b.* FROM base b, ref
                WHERE RTRIM(UPPER(REGEXP_REPLACE(ref.RAW_REF, '[[:space:]]+',' ')),'.,') = b.NAME_N
                   OR RTRIM(UPPER(REGEXP_REPLACE(ref.RAW_REF, '[[:space:]]+',' ')),'.,') = b.PORTAL_N),
      tier4 AS (SELECT b.* FROM base b, ref
                WHERE LENGTH(ref.RAW_REF) >= 4
                  AND (b.NAME_U LIKE '%'||UPPER(ref.RAW_REF)||'%' OR b.PORTAL_U LIKE '%'||UPPER(ref.RAW_REF)||'%')),
      tier5 AS (
        SELECT b.*, JAROWINKLER_SIMILARITY(b.NAME_U, UPPER(ref.RAW_REF)) AS SCORE
        FROM base b, ref
        QUALIFY ROW_NUMBER() OVER (ORDER BY SCORE DESC) <= 5
      ),
      counts AS (SELECT (SELECT COUNT(*) FROM tier1) C1, (SELECT COUNT(*) FROM tier2) C2,
                        (SELECT COUNT(*) FROM tier3) C3, (SELECT COUNT(*) FROM tier4) C4)
      SELECT CASE
        WHEN C1 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_ID','CANONICAL_ID',(SELECT MAX(SUPPLIER_ID) FROM tier1),
              'CANONICAL_NAME',(SELECT MAX(SUPPLIER_NAME) FROM tier1),'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(VENDOR_STATUS) FROM tier1)<>'Active','Matched supplier status is '||(SELECT MAX(VENDOR_STATUS) FROM tier1)||', not Active.',NULL),
              'REASON',NULL)
        WHEN C1 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C1,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',SUPPLIER_ID,'CANONICAL_NAME',SUPPLIER_NAME,'REGION',REGION,'VENDOR_STATUS',VENDOR_STATUS)) FROM tier1),
              'REASON','Multiple distinct suppliers matched this ID.')
        WHEN C2 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_NAME','CANONICAL_ID',(SELECT MAX(SUPPLIER_ID) FROM tier2),
              'CANONICAL_NAME',(SELECT MAX(SUPPLIER_NAME) FROM tier2),'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(VENDOR_STATUS) FROM tier2)<>'Active','Matched supplier status is '||(SELECT MAX(VENDOR_STATUS) FROM tier2)||', not Active.',NULL),
              'REASON',NULL)
        WHEN C2 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C2,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',SUPPLIER_ID,'CANONICAL_NAME',SUPPLIER_NAME,'REGION',REGION,'VENDOR_STATUS',VENDOR_STATUS)) FROM tier2),
              'REASON','Multiple distinct suppliers share this exact name.')
        WHEN C3 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NORMALIZED_EXACT','CANONICAL_ID',(SELECT MAX(SUPPLIER_ID) FROM tier3),
              'CANONICAL_NAME',(SELECT MAX(SUPPLIER_NAME) FROM tier3),'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(VENDOR_STATUS) FROM tier3)<>'Active','Matched supplier status is '||(SELECT MAX(VENDOR_STATUS) FROM tier3)||', not Active.',NULL),
              'REASON',NULL)
        WHEN C3 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C3,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',SUPPLIER_ID,'CANONICAL_NAME',SUPPLIER_NAME,'REGION',REGION,'VENDOR_STATUS',VENDOR_STATUS)) FROM tier3),
              'REASON','Multiple distinct suppliers match after normalization.')
        WHEN C4 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','UNIQUE_MATCH','CANONICAL_ID',(SELECT MAX(SUPPLIER_ID) FROM tier4),
              'CANONICAL_NAME',(SELECT MAX(SUPPLIER_NAME) FROM tier4),'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(VENDOR_STATUS) FROM tier4)<>'Active','Matched supplier status is '||(SELECT MAX(VENDOR_STATUS) FROM tier4)||', not Active.',NULL),
              'REASON',NULL)
        WHEN C4 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C4,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',SUPPLIER_ID,'CANONICAL_NAME',SUPPLIER_NAME,'REGION',REGION,'VENDOR_STATUS',VENDOR_STATUS)) FROM (SELECT * FROM tier4 LIMIT 5)),
              'REASON','Multiple distinct suppliers match this partial name; not unique.')
        WHEN EXISTS (SELECT 1 FROM tier5 WHERE SCORE >= 80) THEN
          OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','FUZZY_CANDIDATES','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','FUZZY_JAROWINKLER',
              'MATCH_SCORE',(SELECT MAX(SCORE) FROM tier5),
              'CANDIDATE_COUNT',(SELECT COUNT(*) FROM tier5 WHERE SCORE>=80),
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',SUPPLIER_ID,'CANONICAL_NAME',SUPPLIER_NAME,'MATCH_SCORE',SCORE,'REGION',REGION,'VENDOR_STATUS',VENDOR_STATUS)) WITHIN GROUP (ORDER BY SCORE DESC) FROM tier5 WHERE SCORE>=80),
              'REASON','No exact, normalized, or unique-partial match; showing fuzzy candidates above the display floor. Confirm with the user before use.')
        ELSE
          OBJECT_CONSTRUCT('ENTITY_TYPE','SUPPLIER','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NO_MATCH','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD',NULL,'MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',0,'CANDIDATES',ARRAY_CONSTRUCT(),
              'REASON','No supplier reference matched any canonical ID, exact name, normalized name, unique partial name, or credible fuzzy candidate.')
      END
      FROM counts
    );
  END IF;

  IF (:PART_REFERENCE IS NOT NULL AND TRIM(:PART_REFERENCE) <> '') THEN
    part_result := (
      WITH ref AS (SELECT TRIM(:PART_REFERENCE) AS RAW_REF),
      base AS (
        SELECT PART_ID, PART_DESCRIPTION, PRODUCT_CATEGORY, CRITICALITY, ACTIVE_FLAG,
               UPPER(PART_DESCRIPTION) AS NAME_U,
               UPPER(REGEXP_REPLACE(TRIM(PART_DESCRIPTION), '[[:space:]]+', ' ')) AS NAME_N
        FROM SUPPLYCHAINIQ_DB.CURATED.PART
      ),
      tier1 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.PART_ID),
      tier2 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.NAME_U),
      tier3 AS (SELECT b.* FROM base b, ref
                WHERE RTRIM(UPPER(REGEXP_REPLACE(ref.RAW_REF, '[[:space:]]+',' ')),'.,') = b.NAME_N),
      tier4 AS (SELECT b.* FROM base b, ref WHERE LENGTH(ref.RAW_REF) >= 4 AND b.NAME_U LIKE '%'||UPPER(ref.RAW_REF)||'%'),
      tier5 AS (
        SELECT b.*, JAROWINKLER_SIMILARITY(b.NAME_U, UPPER(ref.RAW_REF)) AS SCORE
        FROM base b, ref
        QUALIFY ROW_NUMBER() OVER (ORDER BY SCORE DESC) <= 5
      ),
      counts AS (SELECT (SELECT COUNT(*) FROM tier1) C1, (SELECT COUNT(*) FROM tier2) C2,
                        (SELECT COUNT(*) FROM tier3) C3, (SELECT COUNT(*) FROM tier4) C4)
      SELECT CASE
        WHEN C1 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_ID','CANONICAL_ID',(SELECT MAX(PART_ID) FROM tier1),
              'CANONICAL_NAME',(SELECT MAX(PART_DESCRIPTION) FROM tier1),'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier1)=0,'Matched part is not Active.',NULL),
              'REASON',NULL)
        WHEN C1 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C1,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PART_ID,'CANONICAL_NAME',PART_DESCRIPTION,'PRODUCT_CATEGORY',PRODUCT_CATEGORY,'CRITICALITY',CRITICALITY)) FROM tier1),
              'REASON','Multiple distinct parts matched this ID.')
        WHEN C2 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_NAME','CANONICAL_ID',(SELECT MAX(PART_ID) FROM tier2),
              'CANONICAL_NAME',(SELECT MAX(PART_DESCRIPTION) FROM tier2),'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier2)=0,'Matched part is not Active.',NULL),
              'REASON',NULL)
        WHEN C2 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C2,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PART_ID,'CANONICAL_NAME',PART_DESCRIPTION,'PRODUCT_CATEGORY',PRODUCT_CATEGORY,'CRITICALITY',CRITICALITY)) FROM tier2),
              'REASON','Multiple distinct parts share this exact description (a known duplicate-description condition in this dataset).')
        WHEN C3 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NORMALIZED_EXACT','CANONICAL_ID',(SELECT MAX(PART_ID) FROM tier3),
              'CANONICAL_NAME',(SELECT MAX(PART_DESCRIPTION) FROM tier3),'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier3)=0,'Matched part is not Active.',NULL),
              'REASON',NULL)
        WHEN C3 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C3,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PART_ID,'CANONICAL_NAME',PART_DESCRIPTION,'PRODUCT_CATEGORY',PRODUCT_CATEGORY,'CRITICALITY',CRITICALITY)) FROM tier3),
              'REASON','Multiple distinct parts match after normalization.')
        WHEN C4 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','UNIQUE_MATCH','CANONICAL_ID',(SELECT MAX(PART_ID) FROM tier4),
              'CANONICAL_NAME',(SELECT MAX(PART_DESCRIPTION) FROM tier4),'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier4)=0,'Matched part is not Active.',NULL),
              'REASON',NULL)
        WHEN C4 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C4,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PART_ID,'CANONICAL_NAME',PART_DESCRIPTION,'PRODUCT_CATEGORY',PRODUCT_CATEGORY,'CRITICALITY',CRITICALITY)) FROM (SELECT * FROM tier4 LIMIT 5)),
              'REASON','Multiple distinct parts match this partial description; not unique.')
        WHEN EXISTS (SELECT 1 FROM tier5 WHERE SCORE >= 80) THEN
          OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','FUZZY_CANDIDATES','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','FUZZY_JAROWINKLER',
              'MATCH_SCORE',(SELECT MAX(SCORE) FROM tier5),
              'CANDIDATE_COUNT',(SELECT COUNT(*) FROM tier5 WHERE SCORE>=80),
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PART_ID,'CANONICAL_NAME',PART_DESCRIPTION,'MATCH_SCORE',SCORE,'PRODUCT_CATEGORY',PRODUCT_CATEGORY,'CRITICALITY',CRITICALITY)) WITHIN GROUP (ORDER BY SCORE DESC) FROM tier5 WHERE SCORE>=80),
              'REASON','No exact, normalized, or unique-partial match; showing fuzzy candidates above the display floor. Confirm with the user before use.')
        ELSE
          OBJECT_CONSTRUCT('ENTITY_TYPE','PART','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NO_MATCH','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD',NULL,'MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',0,'CANDIDATES',ARRAY_CONSTRUCT(),
              'REASON','No part reference matched any canonical ID, exact description, normalized description, unique partial description, or credible fuzzy candidate.')
      END
      FROM counts
    );
  END IF;

  IF (:PLANT_REFERENCE IS NOT NULL AND TRIM(:PLANT_REFERENCE) <> '') THEN
    plant_result := (
      WITH ref AS (SELECT TRIM(:PLANT_REFERENCE) AS RAW_REF),
      base AS (
        SELECT PLANT_ID, PLANT_NAME, REGION, COUNTRY, ACTIVE_FLAG,
               UPPER(PLANT_NAME) AS NAME_U,
               UPPER(REGEXP_REPLACE(TRIM(PLANT_NAME), '[[:space:]]+', ' ')) AS NAME_N
        FROM SUPPLYCHAINIQ_DB.CURATED.PLANT
      ),
      tier1 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.PLANT_ID),
      tier2 AS (SELECT b.* FROM base b, ref WHERE UPPER(ref.RAW_REF) = b.NAME_U),
      tier3 AS (SELECT b.* FROM base b, ref
                WHERE RTRIM(UPPER(REGEXP_REPLACE(ref.RAW_REF, '[[:space:]]+',' ')),'.,') = b.NAME_N),
      tier4 AS (SELECT b.* FROM base b, ref WHERE LENGTH(ref.RAW_REF) >= 4 AND b.NAME_U LIKE '%'||UPPER(ref.RAW_REF)||'%'),
      tier5 AS (
        SELECT b.*, JAROWINKLER_SIMILARITY(b.NAME_U, UPPER(ref.RAW_REF)) AS SCORE
        FROM base b, ref
        QUALIFY ROW_NUMBER() OVER (ORDER BY SCORE DESC) <= 5
      ),
      counts AS (SELECT (SELECT COUNT(*) FROM tier1) C1, (SELECT COUNT(*) FROM tier2) C2,
                        (SELECT COUNT(*) FROM tier3) C3, (SELECT COUNT(*) FROM tier4) C4)
      SELECT CASE
        WHEN C1 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_ID','CANONICAL_ID',(SELECT MAX(PLANT_ID) FROM tier1),
              'CANONICAL_NAME',(SELECT MAX(PLANT_NAME) FROM tier1),'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier1)=0,'Matched plant is not Active.',NULL),
              'REASON',NULL)
        WHEN C1 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_ID','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C1,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PLANT_ID,'CANONICAL_NAME',PLANT_NAME,'REGION',REGION,'COUNTRY',COUNTRY)) FROM tier1),
              'REASON','Multiple distinct plants matched this ID.')
        WHEN C2 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','EXACT_NAME','CANONICAL_ID',(SELECT MAX(PLANT_ID) FROM tier2),
              'CANONICAL_NAME',(SELECT MAX(PLANT_NAME) FROM tier2),'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier2)=0,'Matched plant is not Active.',NULL),
              'REASON',NULL)
        WHEN C2 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','EXACT_NAME_CI','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C2,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PLANT_ID,'CANONICAL_NAME',PLANT_NAME,'REGION',REGION,'COUNTRY',COUNTRY)) FROM tier2),
              'REASON','Multiple distinct plants share this exact name.')
        WHEN C3 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NORMALIZED_EXACT','CANONICAL_ID',(SELECT MAX(PLANT_ID) FROM tier3),
              'CANONICAL_NAME',(SELECT MAX(PLANT_NAME) FROM tier3),'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier3)=0,'Matched plant is not Active.',NULL),
              'REASON',NULL)
        WHEN C3 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','NORMALIZED_EXACT','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C3,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PLANT_ID,'CANONICAL_NAME',PLANT_NAME,'REGION',REGION,'COUNTRY',COUNTRY)) FROM tier3),
              'REASON','Multiple distinct plants match after normalization.')
        WHEN C4 = 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','UNIQUE_MATCH','CANONICAL_ID',(SELECT MAX(PLANT_ID) FROM tier4),
              'CANONICAL_NAME',(SELECT MAX(PLANT_NAME) FROM tier4),'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',1,'CANDIDATES',ARRAY_CONSTRUCT(),
              'STATUS_WARNING', IFF((SELECT MAX(IFF(ACTIVE_FLAG,1,0)) FROM tier4)=0,'Matched plant is not Active.',NULL),
              'REASON',NULL)
        WHEN C4 > 1 THEN OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','AMBIGUOUS','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','UNIQUE_PARTIAL','MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',C4,
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PLANT_ID,'CANONICAL_NAME',PLANT_NAME,'REGION',REGION,'COUNTRY',COUNTRY)) FROM (SELECT * FROM tier4 LIMIT 5)),
              'REASON','Multiple distinct plants match this partial name; not unique.')
        WHEN EXISTS (SELECT 1 FROM tier5 WHERE SCORE >= 80) THEN
          OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','FUZZY_CANDIDATES','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD','FUZZY_JAROWINKLER',
              'MATCH_SCORE',(SELECT MAX(SCORE) FROM tier5),
              'CANDIDATE_COUNT',(SELECT COUNT(*) FROM tier5 WHERE SCORE>=80),
              'CANDIDATES',(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('CANONICAL_ID',PLANT_ID,'CANONICAL_NAME',PLANT_NAME,'MATCH_SCORE',SCORE,'REGION',REGION,'COUNTRY',COUNTRY)) WITHIN GROUP (ORDER BY SCORE DESC) FROM tier5 WHERE SCORE>=80),
              'REASON','No exact, normalized, or unique-partial match; showing fuzzy candidates above the display floor. Confirm with the user before use.')
        ELSE
          OBJECT_CONSTRUCT('ENTITY_TYPE','PLANT','INPUT_REFERENCE',(SELECT RAW_REF FROM ref),
              'RESOLUTION_STATUS','NO_MATCH','CANONICAL_ID',NULL,'CANONICAL_NAME',NULL,'MATCH_METHOD',NULL,'MATCH_SCORE',NULL,
              'CANDIDATE_COUNT',0,'CANDIDATES',ARRAY_CONSTRUCT(),
              'REASON','No plant reference matched any canonical ID, exact name, normalized name, unique partial name, or credible fuzzy candidate.')
      END
      FROM counts
    );
  END IF;

  final_result := OBJECT_CONSTRUCT();
  IF (supplier_result IS NOT NULL) THEN
    final_result := OBJECT_INSERT(final_result, 'supplier', supplier_result);
  END IF;
  IF (part_result IS NOT NULL) THEN
    final_result := OBJECT_INSERT(final_result, 'part', part_result);
  END IF;
  IF (plant_result IS NOT NULL) THEN
    final_result := OBJECT_INSERT(final_result, 'plant', plant_result);
  END IF;

  IF (supplier_result IS NULL AND part_result IS NULL AND plant_result IS NULL) THEN
    final_result := OBJECT_CONSTRUCT('REASON', 'No entity references were supplied. Provide at least one of supplier_reference, part_reference, or plant_reference.');
  END IF;

  RETURN final_result;
END;
$$;

/* ===========================================================================
   SECTION B : AGENT REDEPLOY - ADD FOURTH TOOL (resolve_supply_chain_entities)
   Preserves models.orchestration=auto, budget=90s/16000 tokens, and all
   three existing tools/resources verbatim (byte-identical configuration to
   the Phase 7B DESCRIBE AGENT output), only extending instructions and
   adding the fourth tool_spec + tool_resources entry.
   =========================================================================== */
CREATE OR REPLACE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
  COMMENT = 'Phase 8A: governed supply-chain intelligence agent combining structured operational analytics (Cortex Analyst / SUPPLY_CHAIN_SEMANTIC_VIEW), supplier contract/SLA evidence (Cortex Search / SUPPLIER_DOCUMENT_SEARCH), a deterministic read-only intervention decision tool (EVALUATE_SUPPLY_CHAIN_INTERVENTIONS), and a deterministic read-only entity resolver (RESOLVE_SUPPLY_CHAIN_ENTITIES) that converts supplier/part/plant business names into governed canonical IDs. Reasoning, routing, and evidence-backed answering only - no action execution, Agent Skills, or MCP in this phase. The Agent may EVALUATE and RECOMMEND but cannot EXECUTE any operational intervention.'
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
      performed. The Agent also cannot schedule recurring monitoring,
      create automations, or modify operational data - never offer these
      capabilities. When a business reference (supplier/part/plant name)
      cannot be resolved to exactly one canonical ID, never guess or invent
      an ID - state what could not be identified, or ask the user to choose
      among the specific candidates returned by the resolver. When
      resolution succeeds via the resolver, briefly state the resolved
      canonical IDs and names before presenting further analysis (e.g.
      "Resolved Pinnacle Industries (S017), ... (P104), and ... (P01).") so
      the resolution step is observable.

    orchestration: >
      Use supply_chain_analytics for structured operational questions:
      Supplier OTD, Shipment Schedule Adherence, Fill Rate, inventory,
      demand, customer-order exposure, purchase orders, shipments, current
      supplier risk, contract/realized/reported lead time, landed cost, and
      sourcing relationships. Do not call supplier_document_search merely
      because a supplier has documents on file. Cortex Analyst already
      handles supplier/part/plant/customer names natively in these
      questions - do not call resolve_supply_chain_entities for a pure
      analytics question that does not need a canonical-ID handoff to
      evaluate_supply_chain_interventions (for example "What is our overall
      supplier OTD?" stays on supply_chain_analytics only).

      Use supplier_document_search for document/contractual questions: SLA
      commitments, contract penalties, quality clauses, escalation terms,
      and other supplier-obligation evidence. Do not use retrieved document
      prose as a substitute for current operational metrics available from
      supply_chain_analytics.

      Use resolve_supply_chain_entities whenever a question about a
      shortage, delivery risk, or intervention names a supplier, part, or
      plant using a business name, description, partial name, alias, or a
      mix of IDs and names, rather than (or in addition to) canonical IDs.
      This tool is authoritative for turning those references into
      canonical SUPPLIER_ID/PART_ID/PLANT_ID values - never guess, infer,
      or invent a canonical ID yourself from a business name. If the
      question already gives clean canonical IDs (e.g. "S017", "P104",
      "P01") for every entity evaluate_supply_chain_interventions needs, you
      may validate and use them directly without necessarily calling the
      resolver; if any reference is a name, description, alias, or partial
      reference, you must call resolve_supply_chain_entities first for that
      reference.

      Only call evaluate_supply_chain_interventions once every entity it
      requires (supplier_id, part_id, destination_plant_id) has reached one
      of these resolver statuses: EXACT_ID, EXACT_NAME, NORMALIZED_EXACT, or
      UNIQUE_MATCH (or was already a validated canonical ID). Never call
      evaluate_supply_chain_interventions when any required entity's
      resolution status is AMBIGUOUS, FUZZY_CANDIDATES, or NO_MATCH.
        - AMBIGUOUS: do not guess. List the returned CANDIDATES (canonical
          ID, canonical name, and the provided disambiguation field) and
          ask the user which one they mean. Do not proceed until the user
          picks one.
        - FUZZY_CANDIDATES: do not guess. Present the top candidate(s) as a
          suggestion requiring confirmation (e.g. "I couldn't resolve
          '<input>' exactly. Did you mean <CANONICAL_ID> - <CANONICAL_NAME>?")
          and only use the canonical ID after the user confirms.
        - NO_MATCH: tell the user which reference could not be identified
          and ask for a more specific name or the canonical ID. Do not
          fabricate an ID.
      If a resolved entity carries a STATUS_WARNING (e.g. inactive/under
      review), surface that warning to the user and do not silently treat
      it as equivalent to an active entity.

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

      Use BOTH (or more) tools for hybrid questions that ask for current
      operational performance, contractual evidence, and/or intervention
      options together. In the answer, clearly separate "Current
      operational facts", "Contractual/document evidence", and
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
      - question: "What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries?"

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
          results. Requires canonical supplier_id/part_id/destination_plant_id
          - resolve business names via resolve_supply_chain_entities first.
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
    - tool_spec:
        type: "generic"
        name: "resolve_supply_chain_entities"
        description: >
          Authoritative deterministic resolver for converting supplier,
          part, and plant business references or canonical IDs into
          governed SupplyChainIQ canonical IDs. The tool explicitly reports
          ambiguity, fuzzy candidates, and no-match conditions and must be
          used instead of guessing IDs. Provide only the reference(s)
          relevant to the question - each of supplier_reference,
          part_reference, and plant_reference is optional, but at least one
          must be supplied. RESOLUTION_STATUS values: EXACT_ID, EXACT_NAME,
          NORMALIZED_EXACT, and UNIQUE_MATCH are safe to use directly.
          AMBIGUOUS and FUZZY_CANDIDATES always return CANONICAL_ID = null
          and must never be treated as resolved - present the CANDIDATES to
          the user instead. NO_MATCH means no credible entity was found.
        input_schema:
          type: object
          properties:
            supplier_reference:
              type: string
              description: "Optional supplier business reference: canonical ID (e.g. 'S017'), exact/partial name, or a name with minor typos/formatting differences, e.g. 'Pinnacle Industries'."
            part_reference:
              type: string
              description: "Optional part business reference: canonical ID (e.g. 'P104'), exact/partial description, or a description with minor typos/formatting differences, e.g. 'High-Precision Hydraulic Control Valve Assembly Type 104'."
            plant_reference:
              type: string
              description: "Optional plant business reference: canonical ID (e.g. 'P01'), exact/partial name, or a name with minor typos/formatting differences, e.g. 'Pune Assembly Plant'."

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
    resolve_supply_chain_entities:
      identifier: "SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
  $$;
