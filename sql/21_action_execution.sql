/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 8C.2 : CONTROLLED ACTION EXECUTION - AUTHORITATIVE DDL
   FILE    : 21_action_execution.sql
   PURPOSE : Create the controlled Snowflake-native DEMO action dispatch layer
             that consumes a human-APPROVED intervention request and creates
             a governed DISPATCHED_DEMO action command. Attaches two new
             tools (execute_approved_intervention, get_intervention_execution
             _status) to the existing SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT.

   SAFETY  : Never mutates SAP_ERP/TMS_LOGISTICS/WMS_INVENTORY/CRM_ORDERS/
             SUPPLIER_PORTAL/DEMAND_PLANNING or any Phase 1 operational
             source table. Never calls an external system (none connected).
             The only writes are: (a) four additive execution-control
             columns on WORKFLOW.INTERVENTION_APPROVAL_REQUEST, (b) rows in
             the new ACTION schema. REVIEW_INTERVENTION_APPROVAL_REQUEST
             remains outside the Agent - no approve/reject/cancel tool
             exists or is added here.

   EMPIRICAL FINDINGS (discovered via live testing, documented rather than
   silently worked around):
   1. Snowflake enforces CHECK (and NOT NULL) constraints on standard
      tables, but does NOT enforce PRIMARY KEY/UNIQUE (reconfirmed from
      Phase 8C.1's audit). The EXECUTION_STATUS CHECK constraint below was
      verified to actually reject an invalid value; the atomic execution
      claim (Section D) therefore relies solely on the conditional UPDATE +
      SQLROWCOUNT pattern, never on any declarative uniqueness constraint.
   2. A Snowflake Scripting variable referenced inside a SELECT / INSERT...
      SELECT statement requires the ":" bind-variable prefix (e.g.
      ":fresh_elem:REASON::STRING"); the same variable referenced directly
      inside a bare RETURN OBJECT_CONSTRUCT(...) expression (not a SELECT)
      does NOT take the prefix. An initial version of this procedure missed
      the prefix inside one INSERT...SELECT event-logging statement,
      raising "invalid identifier 'FRESH_ELEM'". Fixed by precomputing a
      plain scalar variable (fresh_reason) via a colon-prefixed SELECT and
      reusing that variable everywhere, removing the ambiguity.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : ADDITIVE ALTER - execution-control columns on the Phase 8B
   approval request table. REQUEST_STATUS, RECOMMENDATION_SNAPSHOT,
   RECOMMENDATION_HASH, REQUEST_FINGERPRINT, and all human-decision identity
   fields are NEVER touched by this ALTER or by any Phase 8C procedure.
   =========================================================================== */
ALTER TABLE SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
  ADD COLUMN ACTION_ID VARCHAR,
      COLUMN EXECUTION_STATUS VARCHAR DEFAULT 'NOT_DISPATCHED' NOT NULL
        CONSTRAINT CHK_EXECUTION_STATUS CHECK (EXECUTION_STATUS IN ('NOT_DISPATCHED','DISPATCH_CLAIMED','DISPATCHED_DEMO')),
      COLUMN EXECUTION_CLAIMED_AT TIMESTAMP_NTZ,
      COLUMN EXECUTION_AT TIMESTAMP_NTZ;

/* ===========================================================================
   SECTION B : ACTION SCHEMA (create only if absent)
   =========================================================================== */
CREATE SCHEMA IF NOT EXISTS SUPPLYCHAINIQ_DB.ACTION
  COMMENT = 'Phase 8C: controlled Snowflake-native demo action dispatch layer. Consumes human-APPROVED intervention requests and creates governed demo action commands (DISPATCHED_DEMO) representing what a downstream operational adapter would execute. No connection to SAP/TMS/WMS/external systems - never mutates operational source data.';

/* ===========================================================================
   SECTION C : ACTION COMMAND / EVENT TABLES
   =========================================================================== */
CREATE TABLE IF NOT EXISTS SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_COMMAND (
  ACTION_ID VARCHAR PRIMARY KEY,
  REQUEST_ID VARCHAR NOT NULL,
  ACTION_STATUS VARCHAR NOT NULL,
  EXECUTION_MODE VARCHAR NOT NULL,
  SUPPLIER_ID VARCHAR NOT NULL,
  PART_ID VARCHAR NOT NULL,
  DESTINATION_PLANT_ID VARCHAR NOT NULL,
  INTERVENTION_TYPE VARCHAR NOT NULL,
  COMMAND_PAYLOAD VARIANT NOT NULL,
  APPROVED_SNAPSHOT VARIANT NOT NULL,
  APPROVED_SNAPSHOT_HASH VARCHAR NOT NULL,
  FRESH_EVALUATION_SNAPSHOT VARIANT NOT NULL,
  FRESH_EVALUATION_HASH VARCHAR NOT NULL,
  DISPATCHED_BY VARCHAR NOT NULL,
  DISPATCHED_ROLE VARCHAR NOT NULL,
  DISPATCHED_AT TIMESTAMP_NTZ NOT NULL,
  CREATED_AT TIMESTAMP_NTZ NOT NULL,
  UPDATED_AT TIMESTAMP_NTZ NOT NULL
)
COMMENT = 'Phase 8C: durable demo action commands. Only successfully dispatched actions appear here (ACTION_STATUS=DISPATCHED_DEMO) - blocked attempts never materialize a row here, only an event. Declarative PK is documentation-only; Snowflake does not enforce PK/UNIQUE, so uniqueness/concurrency is guaranteed procedurally via the atomic execution claim, not by this constraint.';

CREATE TABLE IF NOT EXISTS SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (
  EVENT_ID VARCHAR PRIMARY KEY,
  ACTION_ID VARCHAR,
  REQUEST_ID VARCHAR NOT NULL,
  EVENT_TYPE VARCHAR NOT NULL,
  EVENT_AT TIMESTAMP_NTZ NOT NULL,
  ACTOR VARCHAR NOT NULL,
  ACTOR_ROLE VARCHAR NOT NULL,
  DETAILS VARCHAR
)
COMMENT = 'Phase 8C: append-only audit trail for execution attempts (BLOCKED_NOT_APPROVED/BLOCKED_HASH_INVALID/BLOCKED_STALE/BLOCKED_INFEASIBLE/BLOCKED_ALREADY_DISPATCHED/DISPATCHED_DEMO). ACTION_ID is NULL for blocked attempts. Never updated or deleted by workflow procedures.';

/* ===========================================================================
   SECTION D : DISPATCH_APPROVED_INTERVENTION (Agent-callable)
   Input: REQUEST_ID only. Never trusts caller-supplied scope/type/quantity/
   cost/mode/snapshot/hash - all authoritative values come from the approved
   request and a fresh, independent deterministic revalidation.
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION(
  REQUEST_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8C: controlled Snowflake-native demo action dispatch. Consumes only REQUEST_ID; every decision fact comes from the human-APPROVED request and a fresh deterministic revalidation - never from the caller. Verifies stored-snapshot hash integrity, freshly re-evaluates feasibility, requires exact hash equality (strict stale-approval rule), and atomically claims one-time execution before creating a demo action command. Never mutates operational source data and never calls an external system.'
EXECUTE AS OWNER
AS
$$
DECLARE
  invoking_user VARCHAR;
  invoking_role VARCHAR;
  now_ts TIMESTAMP_NTZ;
  req_status VARCHAR;
  req_exec_status VARCHAR;
  req_action_id VARCHAR;
  req_supplier VARCHAR;
  req_part VARCHAR;
  req_plant VARCHAR;
  req_type VARCHAR;
  req_snapshot VARIANT;
  req_hash VARCHAR;
  row_found NUMBER;
  approved_canonical_string VARCHAR;
  approved_recomputed_hash VARCHAR;
  eval_result VARIANT;
  fresh_elem VARIANT;
  fresh_feasible BOOLEAN;
  fresh_reason VARCHAR;
  fresh_canonical_string VARCHAR;
  fresh_hash VARCHAR;
  claim_rows NUMBER;
  new_action_id VARCHAR;
  command_payload VARIANT;
BEGIN
  invoking_user := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','PRINCIPAL_NAME'));
  invoking_role := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','ROLE'));
  now_ts := (SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ);

  IF (:REQUEST_ID IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_NOT_APPROVED','REASON','request_id is required.');
  END IF;

  row_found := (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = :REQUEST_ID);
  IF (row_found = 0) THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_NOT_APPROVED', :now_ts, :invoking_user, :invoking_role, 'Request does not exist.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_NOT_APPROVED','REQUEST_ID',:REQUEST_ID,'REASON','Request does not exist.');
  END IF;

  SELECT REQUEST_STATUS, EXECUTION_STATUS, ACTION_ID, SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID,
         SELECTED_INTERVENTION_TYPE, RECOMMENDATION_SNAPSHOT, RECOMMENDATION_HASH
    INTO :req_status, :req_exec_status, :req_action_id, :req_supplier, :req_part, :req_plant,
         :req_type, :req_snapshot, :req_hash
  FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = :REQUEST_ID;

  IF (req_status <> 'APPROVED') THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_NOT_APPROVED', :now_ts, :invoking_user, :invoking_role, 'Request status is '||:req_status||', not APPROVED.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_NOT_APPROVED','REQUEST_ID',:REQUEST_ID,
      'REASON','Request status is '||req_status||', not APPROVED. Only an APPROVED request can be executed.');
  END IF;

  IF (req_exec_status = 'DISPATCHED_DEMO') THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), :req_action_id, :REQUEST_ID, 'BLOCKED_ALREADY_DISPATCHED', :now_ts, :invoking_user, :invoking_role,
           'Request was already dispatched as '||:req_action_id||'.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','ALREADY_DISPATCHED','REQUEST_ID',:REQUEST_ID,'ACTION_ID',req_action_id,
      'MESSAGE','This request was already dispatched to the demo action outbox as '||req_action_id||'. No new action was created.');
  END IF;

  IF (req_exec_status = 'DISPATCH_CLAIMED') THEN
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','DISPATCH_IN_PROGRESS','REQUEST_ID',:REQUEST_ID,
      'REASON','A dispatch for this request is already in progress. Please retry shortly.');
  END IF;

  -- Stored approval snapshot hash-integrity check: recompute using the EXACT Phase 8B canonical order.
  approved_canonical_string := (
    SELECT :req_supplier||'|'||:req_part||'|'||:req_plant||'|'||
      COALESCE(:req_snapshot:INTERVENTION_TYPE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:FEASIBLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:req_snapshot:SOURCE_LOCATION::STRING,'NULL')||'|'||
      COALESCE(:req_snapshot:SOURCE_SUPPLIER::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:QUANTITY_AVAILABLE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:QUANTITY_USED::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:SHORTAGE_BEFORE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:SHORTAGE_AFTER::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:REFERENCE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:ARRIVAL_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:FIRST_CUSTOMER_DUE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:ARRIVES_IN_TIME::BOOLEAN),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:TRANSIT_OR_LEAD_DAYS::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:ESTIMATED_COST::NUMBER),'NULL')||'|'||
      COALESCE(:req_snapshot:CURRENCY::STRING,'NULL')||'|'||
      COALESCE(:req_snapshot:COST_BASIS::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:COST_COMPARABLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:req_snapshot:RISKS_OR_CONSTRAINTS::STRING,'NULL')||'|'||
      COALESCE(:req_snapshot:EVIDENCE_SOURCE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:RECOMMENDATION_RANK::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:req_snapshot:RECOMMENDED::BOOLEAN),'NULL')
  );
  approved_recomputed_hash := (SELECT SHA2(:approved_canonical_string, 256));

  IF (approved_recomputed_hash <> req_hash) THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_HASH_INVALID', :now_ts, :invoking_user, :invoking_role,
           'Recomputed hash of the stored approval snapshot does not match RECOMMENDATION_HASH. The approval record may be corrupted or tampered with.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_HASH_INVALID','REQUEST_ID',:REQUEST_ID,
      'REASON','The stored approval snapshot hash does not match its recomputed value. Execution refused for integrity reasons.');
  END IF;

  -- Fresh deterministic revalidation.
  eval_result := (CALL SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(:req_supplier, :req_part, :req_plant));

  fresh_elem := (
    SELECT VALUE FROM TABLE(FLATTEN(INPUT => :eval_result))
    WHERE VALUE:INTERVENTION_TYPE::STRING = :req_type
    LIMIT 1
  );

  IF (fresh_elem IS NULL) THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_INFEASIBLE', :now_ts, :invoking_user, :invoking_role,
           'The approved intervention type no longer exists in a fresh evaluation for this scope.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_INFEASIBLE','REQUEST_ID',:REQUEST_ID,
      'REASON','The approved intervention type no longer exists in a fresh deterministic evaluation. A new approval is required.');
  END IF;

  fresh_feasible := (SELECT :fresh_elem:FEASIBLE::BOOLEAN);
  fresh_reason := (SELECT COALESCE(:fresh_elem:REASON::STRING,'no reason provided'));
  IF (NOT COALESCE(fresh_feasible, FALSE)) THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_INFEASIBLE', :now_ts, :invoking_user, :invoking_role,
           'Fresh evaluation reports FEASIBLE=FALSE: '||:fresh_reason;
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_INFEASIBLE','REQUEST_ID',:REQUEST_ID,
      'REASON','The approved intervention is no longer feasible: '||fresh_reason||'. A new approval is required.');
  END IF;

  -- Strict stale-approval check: fresh hash must exactly equal the approved hash.
  fresh_canonical_string := (
    SELECT :req_supplier||'|'||:req_part||'|'||:req_plant||'|'||
      COALESCE(:fresh_elem:INTERVENTION_TYPE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:FEASIBLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:fresh_elem:SOURCE_LOCATION::STRING,'NULL')||'|'||
      COALESCE(:fresh_elem:SOURCE_SUPPLIER::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:QUANTITY_AVAILABLE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:QUANTITY_USED::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:SHORTAGE_BEFORE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:SHORTAGE_AFTER::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:REFERENCE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:ARRIVAL_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:FIRST_CUSTOMER_DUE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:ARRIVES_IN_TIME::BOOLEAN),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:TRANSIT_OR_LEAD_DAYS::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:ESTIMATED_COST::NUMBER),'NULL')||'|'||
      COALESCE(:fresh_elem:CURRENCY::STRING,'NULL')||'|'||
      COALESCE(:fresh_elem:COST_BASIS::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:COST_COMPARABLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:fresh_elem:RISKS_OR_CONSTRAINTS::STRING,'NULL')||'|'||
      COALESCE(:fresh_elem:EVIDENCE_SOURCE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:RECOMMENDATION_RANK::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:fresh_elem:RECOMMENDED::BOOLEAN),'NULL')
  );
  fresh_hash := (SELECT SHA2(:fresh_canonical_string, 256));

  IF (fresh_hash <> req_hash) THEN
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS)
    SELECT UUID_STRING(), NULL, :REQUEST_ID, 'BLOCKED_STALE', :now_ts, :invoking_user, :invoking_role,
           'Fresh evaluation hash differs from the approved RECOMMENDATION_HASH. Operational evidence has changed since approval.';
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','BLOCKED_STALE','REQUEST_ID',:REQUEST_ID,
      'REASON','The operational evidence for this intervention has changed since it was approved. A fresh approval request is required before this can be dispatched.');
  END IF;

  -- Atomic execution claim: authoritative concurrency gate. Never rely on PK/UNIQUE.
  UPDATE SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
    SET EXECUTION_STATUS = 'DISPATCH_CLAIMED', EXECUTION_CLAIMED_AT = :now_ts, UPDATED_AT = :now_ts
    WHERE REQUEST_ID = :REQUEST_ID AND REQUEST_STATUS = 'APPROVED' AND EXECUTION_STATUS = 'NOT_DISPATCHED';

  claim_rows := SQLROWCOUNT;

  IF (claim_rows <> 1) THEN
    RETURN OBJECT_CONSTRUCT('ACTION_STATUS','DISPATCH_IN_PROGRESS','REQUEST_ID',:REQUEST_ID,
      'REASON','Could not claim this request for dispatch (it may already be dispatched or a concurrent dispatch is in progress). Please check status and retry if appropriate.');
  END IF;

  new_action_id := (SELECT 'AC-' || UUID_STRING());

  command_payload := OBJECT_CONSTRUCT(
    'request_id', :REQUEST_ID,
    'intervention_type', :req_type,
    'supplier_id', :req_supplier,
    'part_id', :req_part,
    'destination_plant_id', :req_plant,
    'quantity', req_snapshot:QUANTITY_USED,
    'source_supplier', req_snapshot:SOURCE_SUPPLIER,
    'source_location', req_snapshot:SOURCE_LOCATION,
    'reference_date', req_snapshot:REFERENCE_DATE,
    'arrival_date', req_snapshot:ARRIVAL_DATE,
    'transit_or_lead_days', req_snapshot:TRANSIT_OR_LEAD_DAYS,
    'estimated_cost', req_snapshot:ESTIMATED_COST,
    'currency', req_snapshot:CURRENCY,
    'cost_basis', req_snapshot:COST_BASIS,
    'cost_comparable', req_snapshot:COST_COMPARABLE,
    'risks_or_constraints', req_snapshot:RISKS_OR_CONSTRAINTS,
    'execution_mode', 'DEMO'
  );

  BEGIN
    BEGIN TRANSACTION;
    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_COMMAND (
      ACTION_ID, REQUEST_ID, ACTION_STATUS, EXECUTION_MODE, SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID, INTERVENTION_TYPE,
      COMMAND_PAYLOAD, APPROVED_SNAPSHOT, APPROVED_SNAPSHOT_HASH, FRESH_EVALUATION_SNAPSHOT, FRESH_EVALUATION_HASH,
      DISPATCHED_BY, DISPATCHED_ROLE, DISPATCHED_AT, CREATED_AT, UPDATED_AT
    )
    SELECT :new_action_id, :REQUEST_ID, 'DISPATCHED_DEMO', 'DEMO', :req_supplier, :req_part, :req_plant, :req_type,
      :command_payload, :req_snapshot, :req_hash, :fresh_elem, :fresh_hash,
      :invoking_user, :invoking_role, :now_ts, :now_ts, :now_ts;

    INSERT INTO SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_EVENT (
      EVENT_ID, ACTION_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, DETAILS
    )
    SELECT UUID_STRING(), :new_action_id, :REQUEST_ID, 'DISPATCHED_DEMO', :now_ts, :invoking_user, :invoking_role,
           'Demo action command '||:new_action_id||' created for '||:req_type||'.';

    UPDATE SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
      SET EXECUTION_STATUS = 'DISPATCHED_DEMO', ACTION_ID = :new_action_id, EXECUTION_AT = :now_ts, UPDATED_AT = :now_ts
      WHERE REQUEST_ID = :REQUEST_ID;
    COMMIT;
  EXCEPTION
    WHEN OTHER THEN
      ROLLBACK;
      RETURN OBJECT_CONSTRUCT('ACTION_STATUS','ERROR','REQUEST_ID',:REQUEST_ID,'REASON','Failed to create action command: '||:SQLERRM);
  END;

  RETURN OBJECT_CONSTRUCT(
    'ACTION_STATUS','DISPATCHED_DEMO','ACTION_ID',new_action_id,'REQUEST_ID',:REQUEST_ID,
    'SUPPLIER_ID',:req_supplier,'PART_ID',:req_part,'DESTINATION_PLANT_ID',:req_plant,'INTERVENTION_TYPE',:req_type,
    'DISPATCHED_BY',invoking_user,'DISPATCHED_ROLE',invoking_role,'DISPATCHED_AT',now_ts::VARCHAR,
    'MESSAGE','Approved request '||:REQUEST_ID||' was dispatched to the SupplyChainIQ demo action outbox as action '||new_action_id||'. Status: DISPATCHED_DEMO. No SAP/TMS/WMS record was modified and no external operational system was called.'
  );
END;
$$;

/* ===========================================================================
   SECTION E : GET_INTERVENTION_EXECUTION_STATUS (Agent-callable, read-only)
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.ACTION.GET_INTERVENTION_EXECUTION_STATUS(
  REQUEST_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8C: read-only governed execution-status lookup. Joins approval status with action-dispatch status by REQUEST_ID. Owner-rights mediated so callers need no direct SELECT on WORKFLOW/ACTION tables.'
EXECUTE AS OWNER
AS
$$
DECLARE
  row_found NUMBER;
  result VARIANT;
BEGIN
  IF (:REQUEST_ID IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','NOT_FOUND','REASON','request_id is required.');
  END IF;

  row_found := (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = :REQUEST_ID);
  IF (row_found = 0) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','NOT_FOUND','REQUEST_ID',:REQUEST_ID,'REASON','No approval request found with this ID.');
  END IF;

  result := (
    SELECT OBJECT_CONSTRUCT(
      'REQUEST_ID', r.REQUEST_ID,
      'APPROVAL_STATUS', r.REQUEST_STATUS,
      'EXECUTION_STATUS', r.EXECUTION_STATUS,
      'ACTION_ID', r.ACTION_ID,
      'ACTION_STATUS', a.ACTION_STATUS,
      'INTERVENTION_TYPE', r.SELECTED_INTERVENTION_TYPE,
      'SUPPLIER_ID', r.SUPPLIER_ID,
      'PART_ID', r.PART_ID,
      'DESTINATION_PLANT_ID', r.DESTINATION_PLANT_ID,
      'DISPATCHED_BY', a.DISPATCHED_BY,
      'DISPATCHED_ROLE', a.DISPATCHED_ROLE,
      'DISPATCHED_AT', a.DISPATCHED_AT::VARCHAR,
      'EXECUTION_MODE', a.EXECUTION_MODE,
      'OPERATIONAL_SOURCE_SYSTEM_MODIFIED', FALSE
    )
    FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST r
    LEFT JOIN SUPPLYCHAINIQ_DB.ACTION.INTERVENTION_ACTION_COMMAND a ON a.ACTION_ID = r.ACTION_ID
    WHERE r.REQUEST_ID = :REQUEST_ID
  );
  RETURN result;
END;
$$;

/* ===========================================================================
   SECTION F : AGENT REDEPLOY - ADD 7TH/8TH TOOLS
   Preserves models.orchestration=auto, budget=90s/16000 tokens, and all six
   existing tools/resources verbatim, only extending instructions and adding
   execute_approved_intervention + get_intervention_execution_status.
   NOTE: REVIEW_INTERVENTION_APPROVAL_REQUEST is intentionally absent from
   both tools and tool_resources below - it must never be Agent-callable.
   =========================================================================== */
CREATE OR REPLACE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
  COMMENT = 'Phase 8C: governed supply-chain intelligence agent combining structured operational analytics (Cortex Analyst / SUPPLY_CHAIN_SEMANTIC_VIEW), supplier contract/SLA evidence (Cortex Search / SUPPLIER_DOCUMENT_SEARCH), a deterministic read-only intervention decision tool (EVALUATE_SUPPLY_CHAIN_INTERVENTIONS), a deterministic read-only entity resolver (RESOLVE_SUPPLY_CHAIN_ENTITIES), a governed human-approval submission/status workflow (SUBMIT_INTERVENTION_FOR_APPROVAL, GET_INTERVENTION_APPROVAL_STATUS), and a controlled Snowflake-native demo action dispatch layer (EXECUTE_APPROVED_INTERVENTION/DISPATCH_APPROVED_INTERVENTION, GET_INTERVENTION_EXECUTION_STATUS). The Agent may EVALUATE, RECOMMEND, SUBMIT a revalidated recommendation for human approval, and (only on explicit user request, and only for an APPROVED request) DISPATCH a governed Snowflake-native demo action command - it can never itself APPROVE, REJECT, or CANCEL a request, and it never modifies SAP/TMS/WMS or any other operational source system, and never claims a physical external operation occurred.'
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
      options. Every operational intervention must follow this chain:
      RECOMMENDATION -> HUMAN APPROVAL REQUIRED -> (only then, on explicit
      request) CONTROLLED DEMO DISPATCH. The Agent also cannot schedule
      recurring monitoring, create automations, or modify operational data
      outside this governed chain - never offer these capabilities. When a
      business reference (supplier/part/plant name) cannot be resolved to
      exactly one canonical ID, never guess or invent an ID - state what
      could not be identified, or ask the user to choose among the specific
      candidates returned by the resolver. When resolution succeeds via the
      resolver, briefly state the resolved canonical IDs and names before
      presenting further analysis (e.g. "Resolved Pinnacle Industries
      (S017), ... (P104), and ... (P01).") so the resolution step is
      observable. The Agent may CREATE an approval request (via
      submit_intervention_for_approval) only when the user explicitly asks
      to submit/send/request approval for a specific intervention - never
      automatically after merely producing a recommendation. After a
      successful submission, state the exact REQUEST_ID, that its status is
      PENDING, and explicitly that "no operational action has been
      executed." Never say an intervention was "submitted", "ordered", or
      "executed" as if it happened operationally - only an approval request
      was created. The Agent CANNOT approve, reject, or cancel an approval
      request itself, under any phrasing (e.g. "approve this", "just
      approve it yourself") - it must state that a human must review the
      request through a separate process, and it must not attempt any
      workaround. When asked about an approval request's status (via
      get_intervention_approval_status), always state plainly whether it is
      PENDING, APPROVED, REJECTED, or CANCELLED, and always add that
      approval does not mean the intervention has been executed - no
      operational action occurs at any status. The Agent may DISPATCH a
      controlled demo action (via execute_approved_intervention) only when
      the user explicitly asks to execute, dispatch, or proceed with a
      specific already-APPROVED request - never automatically after a
      recommendation, a submission, an approval, or a status lookup. This
      tool only operates on a previously human-approved request: it
      independently re-verifies approval, snapshot integrity, and current
      feasibility, and refuses (without dispatching) if anything has
      changed since approval. It creates ONLY a governed Snowflake-native
      demo action command (an internal outbox record representing what a
      downstream operational adapter would execute in production) - it
      NEVER modifies SAP/TMS/WMS or any other operational source system,
      and NEVER calls an external system, because none is connected in
      this environment. After a successful dispatch, state the exact
      ACTION_ID and that the status is DISPATCHED_DEMO, and explicitly say
      "No SAP/TMS/WMS record was modified and no external operational
      system was called." NEVER say an intervention was "physically
      executed", that "inventory was transferred", that "freight was
      booked", that "a PO was created", or that "the supplier was switched"
      - only a governed demo action command was created. If the tool
      returns BLOCKED_NOT_APPROVED, BLOCKED_HASH_INVALID, BLOCKED_STALE, or
      BLOCKED_INFEASIBLE, relay that governed reason plainly and explain
      that a new approval is required where applicable - never retry
      silently or invent a workaround. If it returns ALREADY_DISPATCHED,
      tell the user the action was already dispatched with that ACTION_ID
      rather than claiming a new dispatch occurred. Use
      get_intervention_execution_status to answer questions about what
      happened to a request's execution (dispatched, blocked, or not yet
      attempted) - this is a pure read and never changes anything; always
      restate that no operational source system was modified regardless of
      status.

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
      evaluate_supply_chain_interventions, submit_intervention_for_approval,
      or execute_approved_intervention (for example "What is our overall
      supplier OTD?" stays on supply_chain_analytics only).

      Use supplier_document_search for document/contractual questions: SLA
      commitments, contract penalties, quality clauses, escalation terms,
      and other supplier-obligation evidence. Do not use retrieved document
      prose as a substitute for current operational metrics available from
      supply_chain_analytics.

      Use resolve_supply_chain_entities whenever a question about a
      shortage, delivery risk, intervention, approval submission, or
      execution names a supplier, part, or plant using a business name,
      description, partial name, alias, or a mix of IDs and names, rather
      than (or in addition to) canonical IDs. This tool is authoritative
      for turning those references into canonical
      SUPPLIER_ID/PART_ID/PLANT_ID values - never guess, infer, or invent a
      canonical ID yourself from a business name. If the question already
      gives clean canonical IDs (e.g. "S017", "P104", "P01") for every
      entity needed, you may validate and use them directly without
      necessarily calling the resolver; if any reference is a name,
      description, alias, or partial reference, you must call
      resolve_supply_chain_entities first for that reference. Note that
      execute_approved_intervention needs only a REQUEST_ID (e.g.
      "AR-..."), never a supplier/part/plant reference - the resolver is
      not needed for execution itself, only for questions that still need
      to identify the underlying scope (e.g. recommending, submitting).

      Only call evaluate_supply_chain_interventions or
      submit_intervention_for_approval once every entity they require
      (supplier_id, part_id, destination_plant_id) has reached one of these
      resolver statuses: EXACT_ID, EXACT_NAME, NORMALIZED_EXACT, or
      UNIQUE_MATCH (or was already a validated canonical ID). Never call
      either tool when any required entity's resolution status is
      AMBIGUOUS, FUZZY_CANDIDATES, or NO_MATCH.
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

      Use submit_intervention_for_approval ONLY when the user explicitly
      asks to submit, send, create an approval request for, or request
      approval for a specific intervention option - for example "Submit the
      recommended option for approval", "Send the P03 transfer for
      approval", "Create an approval request for the alternate supplier
      option". Do NOT call this tool merely because you produced or
      discussed a recommendation - questions like "What do you recommend?",
      "Compare the interventions", "What's the fastest option?", or "Why is
      Road preferred?" must NEVER trigger a submission. Pass only
      supplier_id, part_id, destination_plant_id, and
      selected_intervention_type (the INTERVENTION_TYPE of whichever option
      the user wants submitted - the RECOMMENDED one if they said
      "recommended option", or a specific named type/rank otherwise); the
      tool independently revalidates feasibility and derives every other
      decision fact itself - never supply or assume quantity, cost, dates,
      or feasibility yourself. If the tool returns STATUS = REJECTED
      (intervention not feasible or does not exist) or STATUS = CONFLICT
      (a pending request already exists with different evidence), relay
      that governed reason to the user plainly - do not retry silently or
      invent a workaround. If it returns an existing PENDING request
      (duplicate-submission protection), tell the user a matching request
      is already pending with that REQUEST_ID rather than claiming a new
      one was created.

      Use get_intervention_approval_status to answer questions about the
      status of a previously created approval request (by REQUEST_ID).
      This is a pure read - it never changes anything.

      Use execute_approved_intervention ONLY when the user explicitly asks
      to execute, dispatch, or proceed with the approved action for a
      specific REQUEST_ID - for example "Execute approved request AR-...",
      "Dispatch approved request AR-...", "Proceed with the approved action
      AR-...". Do NOT call this merely because a request became APPROVED,
      merely because the user asked about its status, or merely because the
      user asked a hypothetical ("What would happen if I execute AR-...?"
      must NOT execute it - explain what would happen instead). Pass only
      the request_id - never supplier_id, part_id, destination_plant_id,
      intervention_type, quantity, cost, mode, snapshot, or hash; all of
      those come exclusively from the approved request and the tool's own
      fresh revalidation.

      Use get_intervention_execution_status to answer questions about the
      status of a previously created approval request (by REQUEST_ID).
      This is a pure read - it never changes anything.

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
      approves, or is "the same as" the tool's structured recommendation,
      and never claim that a human APPROVING or the system DISPATCHING a
      submitted request is proof of contractual authorization either -
      approval and dispatch are decisions about the operational
      recommendation only, not a contractual finding. When the
      operationally recommended mode differs from the mode discussed in
      contract/SLA evidence, explicitly state: (a) which option is
      operationally preferred (from evaluate_supply_chain_interventions),
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
    - tool_spec:
        type: "generic"
        name: "submit_intervention_for_approval"
        description: >
          Creates a governed human-approval request for a specific,
          deterministically feasible intervention. Independently
          re-evaluates the intervention via the authoritative deterministic
          decision layer before creating the request - never trusts
          quantity, cost, dates, rank, or feasibility supplied by the
          caller. Only call this when the user explicitly asks to submit,
          send, or request approval for a specific intervention - never
          automatically after merely producing a recommendation. Returns
          STATUS = PENDING with a REQUEST_ID on success, REJECTED if the
          intervention is infeasible or does not exist, or CONFLICT if a
          pending request already exists for this scope with different
          decision evidence. This tool can only CREATE a request - it
          cannot approve, reject, or cancel one; human approval happens
          through a separate process outside this Agent.
        input_schema:
          type: object
          properties:
            supplier_id:
              type: string
              description: "Canonical supplier identifier, e.g. 'S017'. Resolve via resolve_supply_chain_entities first if given as a business name."
            part_id:
              type: string
              description: "Canonical part identifier, e.g. 'P104'. Resolve via resolve_supply_chain_entities first if given as a business name."
            destination_plant_id:
              type: string
              description: "Canonical destination plant identifier, e.g. 'P01'. Resolve via resolve_supply_chain_entities first if given as a business name."
            selected_intervention_type:
              type: string
              description: "The INTERVENTION_TYPE to submit for approval, exactly as returned by evaluate_supply_chain_interventions (e.g. 'EXPEDITED_REPLENISHMENT', 'INTERPLANT_TRANSFER', 'ALTERNATE_SUPPLIER', 'EXPEDITE_CURRENT_SHIPMENT')."
          required: ["supplier_id", "part_id", "destination_plant_id", "selected_intervention_type"]
    - tool_spec:
        type: "generic"
        name: "get_intervention_approval_status"
        description: >
          Read-only lookup of an approval request's current status by
          REQUEST_ID. Returns PENDING, APPROVED, REJECTED, CANCELLED, or
          NOT_FOUND along with requester/decision metadata. Never changes
          anything. Approval status is never proof that an operational
          action has executed.
        input_schema:
          type: object
          properties:
            request_id:
              type: string
              description: "The approval request ID to look up, e.g. 'AR-...'."
          required: ["request_id"]
    - tool_spec:
        type: "generic"
        name: "execute_approved_intervention"
        description: >
          Creates a controlled Snowflake-native DEMO action command for a
          previously human-APPROVED intervention request. Requires ONLY a
          request_id - never accepts supplier/part/plant/intervention
          type/quantity/cost/mode from the caller; every decision fact comes
          from the approved request and a fresh, independent
          deterministic revalidation performed by this tool itself. It:
          (1) requires REQUEST_STATUS = APPROVED, else BLOCKED_NOT_APPROVED;
          (2) independently recomputes and verifies the stored approval
          snapshot's hash for tamper/corruption detection, else
          BLOCKED_HASH_INVALID; (3) freshly re-evaluates the intervention
          via the deterministic decision layer and requires it to still
          exist and be FEASIBLE, else BLOCKED_INFEASIBLE; (4) requires the
          fresh evaluation's hash to exactly match the approved hash
          (strict - any operational change since approval blocks dispatch),
          else BLOCKED_STALE; (5) atomically claims one-time execution so
          concurrent or repeated calls cannot create duplicate commands. On
          success it creates ONLY a governed Snowflake-native demo action
          command (ACTION_STATUS = DISPATCHED_DEMO) representing what a
          downstream operational adapter would execute in production - it
          does NOT modify SAP/TMS/WMS or any operational source system, and
          does NOT call any external system (none is connected). It never
          proves a physical business action occurred.
        input_schema:
          type: object
          properties:
            request_id:
              type: string
              description: "The APPROVED approval request ID to dispatch, e.g. 'AR-...'."
          required: ["request_id"]
    - tool_spec:
        type: "generic"
        name: "get_intervention_execution_status"
        description: >
          Read-only lookup joining approval status and demo-action-dispatch
          status by REQUEST_ID. Returns the approval status, execution
          status (NOT_DISPATCHED/DISPATCH_CLAIMED/DISPATCHED_DEMO), the
          ACTION_ID and action status if dispatched, and confirms no
          operational source system was modified. Never changes anything.
        input_schema:
          type: object
          properties:
            request_id:
              type: string
              description: "The approval request ID to look up, e.g. 'AR-...'."
          required: ["request_id"]

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
    submit_intervention_for_approval:
      identifier: "SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
    get_intervention_approval_status:
      identifier: "SUPPLYCHAINIQ_DB.WORKFLOW.GET_INTERVENTION_APPROVAL_STATUS"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
    execute_approved_intervention:
      identifier: "SUPPLYCHAINIQ_DB.ACTION.DISPATCH_APPROVED_INTERVENTION"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
    get_intervention_execution_status:
      identifier: "SUPPLYCHAINIQ_DB.ACTION.GET_INTERVENTION_EXECUTION_STATUS"
      type: "procedure"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
        query_timeout: 60
  $$;
