/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 8B.2 : HUMAN APPROVAL WORKFLOW - AUTHORITATIVE DDL
   FILE    : 19_approval_workflow.sql
   PURPOSE : Create the governed human-approval workflow (schema, request +
             event tables, submit/review/status procedures) and attach the
             submit + status tools as a 5th/6th tool on the existing
             SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT. This is the first
             intentional write-capable phase - it creates approval-request
             metadata only. NO operational execution capability exists.

   SAFETY  : REVIEW_INTERVENTION_APPROVAL_REQUEST (the only procedure that
             changes request status) is NEVER attached as an Agent tool.
             The Agent can only CREATE requests and READ status.

   EMPIRICAL FINDINGS (discovered via live testing, documented rather than
   silently worked around):
   1. VARIANT-path expressions (:var:FIELD::TYPE) cannot be used directly in
      an INSERT ... VALUES (...) list - raises "Invalid expression [...] in
      VALUES clause". Fixed by using INSERT ... SELECT ... instead, and by
      precomputing scalar values into local variables before use.
   2. "IF (x IS NOT TRUE)" combined directly with a variant-derived boolean
      is not valid Snowflake Scripting syntax here; replaced with
      "IF (NOT COALESCE(x, FALSE))".
   3. A bare function-style call to a stored procedure (proc(args)) is not
      valid; the correct syntax to capture a scalar-returning procedure's
      result is "var := (CALL proc(args));".
   4. Concurrency race in REVIEW_INTERVENTION_APPROVAL_REQUEST: a pre-check
      ("SELECT status; IF <> PENDING THEN error") followed by a separate
      UPDATE is vulnerable to a TOCTOU race if two decisions are issued in
      true parallel against the same request - both can read PENDING before
      either commits. FIXED by making the UPDATE's own
      "WHERE REQUEST_STATUS = 'PENDING'" clause the authoritative gate and
      checking SQLROWCOUNT immediately after: the audit event is inserted
      (and the transaction committed) only if exactly one row was actually
      updated; otherwise ROLLBACK and return a "no longer PENDING" error.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : WORKFLOW SCHEMA (create only if absent)
   =========================================================================== */
CREATE SCHEMA IF NOT EXISTS SUPPLYCHAINIQ_DB.WORKFLOW
  COMMENT = 'Phase 8B: governed human-approval workflow for supply-chain intervention recommendations. Recommendation snapshots and approval decisions only - no operational execution.';

USE SCHEMA WORKFLOW;

/* ===========================================================================
   SECTION B : REQUEST TABLE (current-state row per approval request)
   =========================================================================== */
CREATE TABLE IF NOT EXISTS SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST (
  REQUEST_ID VARCHAR PRIMARY KEY,
  REQUEST_STATUS VARCHAR NOT NULL,
  SUPPLIER_ID VARCHAR NOT NULL,
  PART_ID VARCHAR NOT NULL,
  DESTINATION_PLANT_ID VARCHAR NOT NULL,
  SELECTED_INTERVENTION_TYPE VARCHAR NOT NULL,
  RECOMMENDATION_RANK NUMBER,
  RECOMMENDATION_SNAPSHOT VARIANT NOT NULL,
  RECOMMENDATION_HASH VARCHAR NOT NULL,
  REQUEST_FINGERPRINT VARCHAR NOT NULL,
  DATASET_REFERENCE_DATE DATE,
  REQUESTED_BY VARCHAR NOT NULL,
  REQUESTED_ROLE VARCHAR NOT NULL,
  REQUESTED_AT TIMESTAMP_NTZ NOT NULL,
  APPROVED_OR_REJECTED_BY VARCHAR,
  APPROVER_ROLE VARCHAR,
  DECISION_AT TIMESTAMP_NTZ,
  DECISION_COMMENT VARCHAR,
  CREATED_AT TIMESTAMP_NTZ NOT NULL,
  UPDATED_AT TIMESTAMP_NTZ NOT NULL
)
COMMENT = 'Phase 8B: current-state approval request row. Recommendation-only, no execution fields. REQUEST_STATUS transitions are append-audited in INTERVENTION_APPROVAL_EVENT.';

/* ===========================================================================
   SECTION C : EVENT TABLE (append-only audit trail, never UPDATE/DELETE)
   =========================================================================== */
CREATE TABLE IF NOT EXISTS SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_EVENT (
  EVENT_ID VARCHAR PRIMARY KEY,
  REQUEST_ID VARCHAR NOT NULL,
  EVENT_TYPE VARCHAR NOT NULL,
  EVENT_AT TIMESTAMP_NTZ NOT NULL,
  ACTOR VARCHAR NOT NULL,
  ACTOR_ROLE VARCHAR NOT NULL,
  OLD_STATUS VARCHAR,
  NEW_STATUS VARCHAR NOT NULL,
  COMMENT VARCHAR
)
COMMENT = 'Phase 8B: append-only audit trail for approval-request lifecycle events (REQUEST_CREATED, APPROVED, REJECTED, CANCELLED). Never updated or deleted by workflow procedures.';

/* ===========================================================================
   SECTION D : SUBMIT_INTERVENTION_FOR_APPROVAL (Agent-callable)
   Never trusts caller-supplied quantity/cost/rank/feasibility. Always
   re-derives the snapshot from a fresh EVALUATE_SUPPLY_CHAIN_INTERVENTIONS
   call. Idempotent on exact retry; conflicts (never silently reuses) if
   evidence changed while a PENDING request exists for the same scope+type.
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL(
  SUPPLIER_ID VARCHAR,
  PART_ID VARCHAR,
  DESTINATION_PLANT_ID VARCHAR,
  SELECTED_INTERVENTION_TYPE VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8B: creates a governed approval request for a deterministically-revalidated, feasible intervention. Never trusts LLM-supplied quantity/cost/rank/feasibility - always re-derives the snapshot from a fresh EVALUATE_SUPPLY_CHAIN_INTERVENTIONS call. Idempotent on exact retry; conflicts (does not silently reuse) if evidence changed while a PENDING request exists for the same scope+type.'
EXECUTE AS OWNER
AS
$$
DECLARE
  invoking_user VARCHAR;
  invoking_role VARCHAR;
  eval_result VARIANT;
  selected_elem VARIANT;
  is_feasible BOOLEAN;
  rec_rank NUMBER;
  rec_flag BOOLEAN;
  ref_dt DATE;
  canonical_string VARCHAR;
  canonical_hash VARCHAR;
  new_fingerprint VARCHAR;
  existing_id VARCHAR;
  existing_status VARCHAR;
  existing_hash VARCHAR;
  existing_fingerprint VARCHAR;
  new_request_id VARCHAR;
  now_ts TIMESTAMP_NTZ;
  result VARIANT;
BEGIN
  invoking_user := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','PRINCIPAL_NAME'));
  invoking_role := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','ROLE'));
  now_ts := (SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ);

  IF (:SUPPLIER_ID IS NULL OR :PART_ID IS NULL OR :DESTINATION_PLANT_ID IS NULL OR :SELECTED_INTERVENTION_TYPE IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','REJECTED','REASON','supplier_id, part_id, destination_plant_id, and selected_intervention_type are all required.');
  END IF;

  -- Revalidate deterministically. Never trust LLM-supplied decision facts.
  eval_result := (CALL SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(:SUPPLIER_ID, :PART_ID, :DESTINATION_PLANT_ID));

  selected_elem := (
    SELECT VALUE FROM TABLE(FLATTEN(INPUT => :eval_result))
    WHERE VALUE:INTERVENTION_TYPE::STRING = :SELECTED_INTERVENTION_TYPE
    LIMIT 1
  );

  IF (selected_elem IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','REJECTED',
      'REASON','No intervention of type '||:SELECTED_INTERVENTION_TYPE||' exists for this supplier/part/plant scope.');
  END IF;

  is_feasible := (SELECT :selected_elem:FEASIBLE::BOOLEAN);

  IF (NOT COALESCE(is_feasible, FALSE)) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','REJECTED',
      'REASON','Selected intervention is not currently feasible: '||COALESCE(selected_elem:REASON::STRING,'no reason provided'));
  END IF;

  rec_rank := (SELECT :selected_elem:RECOMMENDATION_RANK::NUMBER);
  rec_flag := (SELECT :selected_elem:RECOMMENDED::BOOLEAN);
  ref_dt := (SELECT :selected_elem:REFERENCE_DATE::DATE);

  -- Canonical hash: fixed field order (documented in docs/approval_workflow_design.md Section 3).
  canonical_string := (
    SELECT :SUPPLIER_ID||'|'||:PART_ID||'|'||:DESTINATION_PLANT_ID||'|'||
      COALESCE(:selected_elem:INTERVENTION_TYPE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:FEASIBLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:selected_elem:SOURCE_LOCATION::STRING,'NULL')||'|'||
      COALESCE(:selected_elem:SOURCE_SUPPLIER::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:QUANTITY_AVAILABLE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:QUANTITY_USED::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:SHORTAGE_BEFORE::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:SHORTAGE_AFTER::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:REFERENCE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:ARRIVAL_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:FIRST_CUSTOMER_DUE_DATE::DATE),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:ARRIVES_IN_TIME::BOOLEAN),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:TRANSIT_OR_LEAD_DAYS::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:ESTIMATED_COST::NUMBER),'NULL')||'|'||
      COALESCE(:selected_elem:CURRENCY::STRING,'NULL')||'|'||
      COALESCE(:selected_elem:COST_BASIS::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:COST_COMPARABLE::BOOLEAN),'NULL')||'|'||
      COALESCE(:selected_elem:RISKS_OR_CONSTRAINTS::STRING,'NULL')||'|'||
      COALESCE(:selected_elem:EVIDENCE_SOURCE::STRING,'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:RECOMMENDATION_RANK::NUMBER),'NULL')||'|'||
      COALESCE(TO_VARCHAR(:selected_elem:RECOMMENDED::BOOLEAN),'NULL')
  );
  canonical_hash := (SELECT SHA2(:canonical_string, 256));
  new_fingerprint := (SELECT SHA2(:SUPPLIER_ID||'|'||:PART_ID||'|'||:DESTINATION_PLANT_ID||'|'||:SELECTED_INTERVENTION_TYPE||'|'||:canonical_hash||'|'||:invoking_user, 256));

  -- Idempotency / conflict check against any existing PENDING request for the same scope+type.
  SELECT REQUEST_ID, REQUEST_STATUS, RECOMMENDATION_HASH, REQUEST_FINGERPRINT
    INTO :existing_id, :existing_status, :existing_hash, :existing_fingerprint
  FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
  WHERE SUPPLIER_ID = :SUPPLIER_ID AND PART_ID = :PART_ID AND DESTINATION_PLANT_ID = :DESTINATION_PLANT_ID
    AND SELECTED_INTERVENTION_TYPE = :SELECTED_INTERVENTION_TYPE AND REQUEST_STATUS = 'PENDING'
  LIMIT 1;

  IF (existing_id IS NOT NULL) THEN
    IF (existing_fingerprint = new_fingerprint) THEN
      RETURN OBJECT_CONSTRUCT('STATUS','PENDING','REQUEST_ID',existing_id,
        'REASON','An identical approval request is already PENDING; returning the existing request rather than creating a duplicate.',
        'SUPPLIER_ID',:SUPPLIER_ID,'PART_ID',:PART_ID,'DESTINATION_PLANT_ID',:DESTINATION_PLANT_ID,
        'SELECTED_INTERVENTION_TYPE',:SELECTED_INTERVENTION_TYPE);
    ELSEIF (existing_hash <> canonical_hash) THEN
      RETURN OBJECT_CONSTRUCT('STATUS','CONFLICT','REQUEST_ID',existing_id,
        'REASON','An approval request is already pending for this intervention, but the current decision evidence has changed. Review or cancel the existing request before submitting the updated recommendation.');
    ELSE
      RETURN OBJECT_CONSTRUCT('STATUS','PENDING','REQUEST_ID',existing_id,
        'REASON','An approval request with unchanged decision evidence is already PENDING for this intervention (submitted by a different requester); returning the existing request rather than creating a duplicate.',
        'SUPPLIER_ID',:SUPPLIER_ID,'PART_ID',:PART_ID,'DESTINATION_PLANT_ID',:DESTINATION_PLANT_ID,
        'SELECTED_INTERVENTION_TYPE',:SELECTED_INTERVENTION_TYPE);
    END IF;
  END IF;

  new_request_id := (SELECT 'AR-' || UUID_STRING());

  BEGIN
    BEGIN TRANSACTION;
    INSERT INTO SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST (
      REQUEST_ID, REQUEST_STATUS, SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID, SELECTED_INTERVENTION_TYPE,
      RECOMMENDATION_RANK, RECOMMENDATION_SNAPSHOT, RECOMMENDATION_HASH, REQUEST_FINGERPRINT, DATASET_REFERENCE_DATE,
      REQUESTED_BY, REQUESTED_ROLE, REQUESTED_AT, CREATED_AT, UPDATED_AT
    )
    SELECT :new_request_id, 'PENDING', :SUPPLIER_ID, :PART_ID, :DESTINATION_PLANT_ID, :SELECTED_INTERVENTION_TYPE,
      :rec_rank, :selected_elem, :canonical_hash, :new_fingerprint,
      :ref_dt, :invoking_user, :invoking_role, :now_ts, :now_ts, :now_ts;

    INSERT INTO SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_EVENT (
      EVENT_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, OLD_STATUS, NEW_STATUS, COMMENT
    )
    SELECT UUID_STRING(), :new_request_id, 'REQUEST_CREATED', :now_ts, :invoking_user, :invoking_role, NULL, 'PENDING', NULL;
    COMMIT;
  EXCEPTION
    WHEN OTHER THEN
      ROLLBACK;
      RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REASON','Failed to create approval request: '||:SQLERRM);
  END;

  result := OBJECT_CONSTRUCT(
    'STATUS','PENDING','REQUEST_ID',new_request_id,
    'SUPPLIER_ID',:SUPPLIER_ID,'PART_ID',:PART_ID,'DESTINATION_PLANT_ID',:DESTINATION_PLANT_ID,
    'SELECTED_INTERVENTION_TYPE',:SELECTED_INTERVENTION_TYPE,
    'RECOMMENDATION_RANK', rec_rank,
    'RECOMMENDED', rec_flag,
    'REQUESTED_BY', invoking_user, 'REQUESTED_ROLE', invoking_role, 'REQUESTED_AT', now_ts::VARCHAR,
    'MESSAGE','Approval request created. No operational action has been executed.'
  );
  RETURN result;
END;
$$;

/* ===========================================================================
   SECTION E : REVIEW_INTERVENTION_APPROVAL_REQUEST (HUMAN-ONLY - NEVER an Agent tool)
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST(
  REQUEST_ID VARCHAR,
  DECISION VARCHAR,
  COMMENT VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8B: HUMAN-ONLY procedure. Never attach as a Cortex Agent tool. Transitions a PENDING approval request to APPROVED/REJECTED/CANCELLED. Only PENDING requests may transition; any decision on a terminal request is rejected, never reopened, never re-eventing. Hardened against concurrent-call races: the UPDATE itself is the authoritative PENDING gate (WHERE REQUEST_STATUS=PENDING), and the event is inserted only if that UPDATE actually affected exactly one row.'
EXECUTE AS OWNER
AS
$$
DECLARE
  actor VARCHAR;
  actor_role VARCHAR;
  now_ts TIMESTAMP_NTZ;
  cur_status VARCHAR;
  new_status VARCHAR;
  row_found NUMBER;
  rows_updated NUMBER;
BEGIN
  actor := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','PRINCIPAL_NAME'));
  actor_role := (SELECT SYS_CONTEXT('SNOWFLAKE$SESSION','ROLE'));
  now_ts := (SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ);

  IF (:REQUEST_ID IS NULL OR :DECISION IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REASON','request_id and decision are required.');
  END IF;

  IF (UPPER(:DECISION) NOT IN ('APPROVE','REJECT','CANCEL')) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REASON','decision must be one of APPROVE, REJECT, CANCEL.');
  END IF;

  new_status := CASE UPPER(:DECISION) WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REJECT' THEN 'REJECTED' WHEN 'CANCEL' THEN 'CANCELLED' END;

  row_found := (SELECT COUNT(*) FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = :REQUEST_ID);
  IF (row_found = 0) THEN
    RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REASON','Request '||:REQUEST_ID||' does not exist.');
  END IF;

  cur_status := (SELECT REQUEST_STATUS FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST WHERE REQUEST_ID = :REQUEST_ID);

  IF (cur_status <> 'PENDING') THEN
    RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REQUEST_ID',:REQUEST_ID,
      'REASON','Request '||:REQUEST_ID||' is already '||cur_status||'; it cannot be re-decided. A changed decision requires a new approval request.');
  END IF;

  BEGIN
    BEGIN TRANSACTION;
    UPDATE SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
      SET REQUEST_STATUS = :new_status,
          APPROVED_OR_REJECTED_BY = :actor,
          APPROVER_ROLE = :actor_role,
          DECISION_AT = :now_ts,
          DECISION_COMMENT = :COMMENT,
          UPDATED_AT = :now_ts
      WHERE REQUEST_ID = :REQUEST_ID AND REQUEST_STATUS = 'PENDING';

    rows_updated := SQLROWCOUNT;

    IF (rows_updated <> 1) THEN
      ROLLBACK;
      RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REQUEST_ID',:REQUEST_ID,
        'REASON','Request '||:REQUEST_ID||' was no longer PENDING at decision time (concurrent decision detected); it cannot be re-decided. A changed decision requires a new approval request.');
    END IF;

    INSERT INTO SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_EVENT (
      EVENT_ID, REQUEST_ID, EVENT_TYPE, EVENT_AT, ACTOR, ACTOR_ROLE, OLD_STATUS, NEW_STATUS, COMMENT
    )
    SELECT UUID_STRING(), :REQUEST_ID, :new_status, :now_ts, :actor, :actor_role, 'PENDING', :new_status, :COMMENT;
    COMMIT;
  EXCEPTION
    WHEN OTHER THEN
      ROLLBACK;
      RETURN OBJECT_CONSTRUCT('STATUS','ERROR','REASON','Failed to record decision: '||:SQLERRM);
  END;

  RETURN OBJECT_CONSTRUCT(
    'STATUS', new_status, 'REQUEST_ID', :REQUEST_ID,
    'APPROVED_OR_REJECTED_BY', actor, 'APPROVER_ROLE', actor_role, 'DECISION_AT', now_ts::VARCHAR,
    'DECISION_COMMENT', :COMMENT,
    'MESSAGE', 'Request '||:REQUEST_ID||' is now '||new_status||'. No operational action has been executed.'
  );
END;
$$;

/* ===========================================================================
   SECTION F : GET_INTERVENTION_APPROVAL_STATUS (Agent-callable, read-only)
   =========================================================================== */
CREATE OR REPLACE PROCEDURE SUPPLYCHAINIQ_DB.WORKFLOW.GET_INTERVENTION_APPROVAL_STATUS(
  REQUEST_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Phase 8B: read-only governed status lookup. Returns only the fields needed to answer a status question - never exposes full workflow-table internals. Owner-rights mediated so callers need no direct SELECT on the workflow tables.'
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
      'REQUEST_ID', REQUEST_ID,
      'REQUEST_STATUS', REQUEST_STATUS,
      'SUPPLIER_ID', SUPPLIER_ID,
      'PART_ID', PART_ID,
      'DESTINATION_PLANT_ID', DESTINATION_PLANT_ID,
      'SELECTED_INTERVENTION_TYPE', SELECTED_INTERVENTION_TYPE,
      'RECOMMENDATION_RANK', RECOMMENDATION_RANK,
      'REQUESTED_BY', REQUESTED_BY,
      'REQUESTED_ROLE', REQUESTED_ROLE,
      'REQUESTED_AT', REQUESTED_AT::VARCHAR,
      'APPROVED_OR_REJECTED_BY', APPROVED_OR_REJECTED_BY,
      'APPROVER_ROLE', APPROVER_ROLE,
      'DECISION_AT', DECISION_AT::VARCHAR,
      'DECISION_COMMENT', DECISION_COMMENT,
      'OPERATIONAL_ACTION_EXECUTED', FALSE
    )
    FROM SUPPLYCHAINIQ_DB.WORKFLOW.INTERVENTION_APPROVAL_REQUEST
    WHERE REQUEST_ID = :REQUEST_ID
  );
  RETURN result;
END;
$$;

/* ===========================================================================
   SECTION G : AGENT REDEPLOY - ADD 5TH/6TH TOOLS
   Preserves models.orchestration=auto, budget=90s/16000 tokens, and all four
   existing tools/resources verbatim, only extending instructions and adding
   submit_intervention_for_approval + get_intervention_approval_status.
   NOTE: REVIEW_INTERVENTION_APPROVAL_REQUEST is intentionally absent from
   both tools and tool_resources below - it must never be Agent-callable.
   =========================================================================== */
CREATE OR REPLACE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
  COMMENT = 'Phase 8B: governed supply-chain intelligence agent combining structured operational analytics (Cortex Analyst / SUPPLY_CHAIN_SEMANTIC_VIEW), supplier contract/SLA evidence (Cortex Search / SUPPLIER_DOCUMENT_SEARCH), a deterministic read-only intervention decision tool (EVALUATE_SUPPLY_CHAIN_INTERVENTIONS), a deterministic read-only entity resolver (RESOLVE_SUPPLY_CHAIN_ENTITIES), and a governed human-approval submission/status workflow (SUBMIT_INTERVENTION_FOR_APPROVAL, GET_INTERVENTION_APPROVAL_STATUS). The Agent may EVALUATE, RECOMMEND, and (only on explicit user request) SUBMIT a revalidated recommendation for human approval - it can never itself APPROVE, REJECT, or CANCEL a request, and it can never EXECUTE any operational intervention.'
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
      the resolution step is observable. The Agent may CREATE an approval
      request (via submit_intervention_for_approval) only when the user
      explicitly asks to submit/send/request approval for a specific
      intervention - never automatically after merely producing a
      recommendation. After a successful submission, state the exact
      REQUEST_ID, that its status is PENDING, and explicitly that "no
      operational action has been executed." Never say an intervention was
      "submitted", "ordered", or "executed" as if it happened operationally
      - only an approval request was created. The Agent CANNOT approve,
      reject, or cancel an approval request itself, under any phrasing
      (e.g. "approve this", "just approve it yourself") - it must state
      that a human must review the request through a separate process, and
      it must not attempt any workaround. When asked about an approval
      request's status (via get_intervention_approval_status), always
      state plainly whether it is PENDING, APPROVED, REJECTED, or
      CANCELLED, and always add that approval does not mean the
      intervention has been executed - no operational action occurs at
      any status.

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
      evaluate_supply_chain_interventions or submit_intervention_for_approval
      (for example "What is our overall supplier OTD?" stays on
      supply_chain_analytics only).

      Use supplier_document_search for document/contractual questions: SLA
      commitments, contract penalties, quality clauses, escalation terms,
      and other supplier-obligation evidence. Do not use retrieved document
      prose as a substitute for current operational metrics available from
      supply_chain_analytics.

      Use resolve_supply_chain_entities whenever a question about a
      shortage, delivery risk, intervention, or approval submission names a
      supplier, part, or plant using a business name, description, partial
      name, alias, or a mix of IDs and names, rather than (or in addition
      to) canonical IDs. This tool is authoritative for turning those
      references into canonical SUPPLIER_ID/PART_ID/PLANT_ID values - never
      guess, infer, or invent a canonical ID yourself from a business name.
      If the question already gives clean canonical IDs (e.g. "S017",
      "P104", "P01") for every entity needed, you may validate and use them
      directly without necessarily calling the resolver; if any reference
      is a name, description, alias, or partial reference, you must call
      resolve_supply_chain_entities first for that reference.

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
      and never claim that a human APPROVING a submitted request is proof
      of contractual authorization either - approval is a decision about
      the operational recommendation only, not a contractual finding. When
      the operationally recommended mode differs from the mode discussed in
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
  $$;
