/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 6B : CORTEX AGENT - AUTHORITATIVE DDL
   FILE    : 13_cortex_agent.sql
   PURPOSE : Create the single governed Cortex Agent that combines structured
             operational analytics (Cortex Analyst over SUPPLY_CHAIN_SEMANTIC_VIEW)
             with unstructured supplier-document evidence (Cortex Search over
             SUPPLIER_DOCUMENT_SEARCH). Reasoning + tool routing + evidence-
             backed answering ONLY - no Agent Skills, action execution, MCP,
             or write-back in this phase.

   SAFETY  : This script only creates SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
             (and the AGENTS schema if absent). It performs no DDL/DML against
             the Semantic View, the Search Service, or any Phase 1-5 object.

   EMPIRICAL BUDGET NOTE: Phase 6A's plan-time estimate of
   orchestration.budget.seconds = 45 was tested against all 12 validation
   questions. It was sufficient for structured-only, Search-only, and most
   hybrid questions, but the flagship hybrid risk scenario ("What
   supply-chain risk from S017 threatens P104 customer deliveries...")
   consistently (3/3 attempts) exceeded 45 seconds - orchestration ("auto")
   selected claude-opus-4-8, which issued ~12 structured SQL calls plus ~6
   Search calls (and, twice, an unsolicited platform chart_instructions
   server-skill invocation) while gathering evidence for this multi-fact
   question, running out of budget before final synthesis. Raised to
   seconds: 90 based on this empirical evidence (no model was pinned; "auto"
   remains in place per the Phase 6A design - only the time budget changed).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION A : AGENTS SCHEMA (create only if absent)
   =========================================================================== */
CREATE SCHEMA IF NOT EXISTS SUPPLYCHAINIQ_DB.AGENTS
  COMMENT = 'Phase 6: Cortex Agent layer combining Cortex Analyst structured analytics and Cortex Search supplier-document evidence.';

USE SCHEMA AGENTS;

/* ===========================================================================
   SECTION B : CORTEX AGENT CREATION
   models.orchestration = "auto" - lets Snowflake select the current
   supported orchestration model rather than pinning a model name that may
   be deprecated mid-hackathon (SHOW CORTEX BASE MODELS confirmed
   CLAUDE-4-SONNET is already LEGACY as of this account's inspection).
   =========================================================================== */

CREATE OR REPLACE AGENT SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT
  COMMENT = 'Phase 6: governed supply-chain intelligence agent combining structured operational analytics (Cortex Analyst / SUPPLY_CHAIN_SEMANTIC_VIEW) with supplier contract/SLA evidence (Cortex Search / SUPPLIER_DOCUMENT_SEARCH). Reasoning, routing, and evidence-backed answering only - no action execution, Agent Skills, or MCP in this phase.'
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
      (from supplier_document_search) - never merge them into a single
      number. Identify every document-backed claim by DOCUMENT_ID and
      DOCUMENT_TYPE (e.g. "According to DOC000217 (SLA)..."), including
      TITLE or SOURCE_REFERENCE when useful. Never fabricate enterprise
      facts or contractual clauses. Preserve document-scope distinctions
      such as a general/portfolio contract versus a part-specific SLA -
      do not average or collapse different scopes into one figure unless
      they genuinely describe the same scope. Never add monetary values
      across different currencies without governed FX conversion data.
      If requested structured data or documentary evidence is unavailable,
      say so explicitly rather than guessing or using general knowledge.

    orchestration: >
      Use supply_chain_analytics for structured operational questions:
      Supplier OTD, Shipment Schedule Adherence, Fill Rate, inventory,
      demand, customer-order exposure, purchase orders, shipments, current
      supplier risk, contract/realized/reported lead time, landed cost, and
      sourcing relationships. Do not call supplier_document_search merely
      because a supplier has documents on file.

      Use supplier_document_search for document/contractual questions: SLA
      commitments, contract penalties, quality clauses, escalation terms,
      and other supplier-obligation evidence. Do not use retrieved document
      prose as a substitute for current operational metrics available from
      supply_chain_analytics.

      Use BOTH tools for hybrid questions that ask for current operational
      performance together with contractual/document evidence (e.g. actual
      OTD vs. contractual OTD, or a risk/exposure question that also asks
      about contract terms). In the answer, clearly separate "Current
      operational facts" from "Contractual/document evidence" - never merge
      them into one number.

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
      calculation.

    sample_questions:
      - question: "What is supplier S017's on-time delivery rate?"
      - question: "What SLA commitments exist for supplier S017?"
      - question: "How is supplier S017 performing against its contractual delivery commitments?"

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
  $$;

SELECT 'Phase 6B / 13_cortex_agent.sql complete - proceed to structural validation (SHOW/DESCRIBE AGENT) then 14_cortex_agent_validation.sql' AS STATUS;
