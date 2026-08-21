# SupplyChainIQ — Cortex Agent Design (Phase 6)

Governed Cortex Agent combining structured operational analytics (Cortex
Analyst) with unstructured supplier-document evidence (Cortex Search).
Reasoning, routing, and evidence-backed answering only — no Agent Skills,
action execution, MCP, write-back, or Streamlit in this phase.

---

## 1. Readiness Audit (reconfirmed in Phase 6B)

| Check | Result |
|---|---|
| `DEFAULT_ROLE` (user ALEN) | ACCOUNTADMIN (matches session role) |
| `DEFAULT_WAREHOUSE` | COMPUTE_WH (matches session warehouse) |
| `AGENTS` schema | Did not exist — created in this phase |
| Semantic View health | ACTIVE, confirmed present pre- and post-creation |
| Cortex Search Service health | ACTIVE/ACTIVE, 139 rows, confirmed present pre- and post-creation |
| Privileges | ACCOUNTADMIN owns `SUPPLYCHAINIQ_DB` (implies CREATE AGENT/SCHEMA), owns `COMPUTE_WH`; `SNOWFLAKE.CORTEX_USER` granted to ACCOUNTADMIN/PUBLIC |

## 2. Agent Object

| Property | Value |
|---|---|
| Object | `SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT` |
| Display name | "SupplyChainIQ Control Tower" |
| Schema created | `SUPPLYCHAINIQ_DB.AGENTS` (new; did not exist before) |
| Orchestration model | `auto` (Snowflake-selected; observed selecting `claude-opus-4-8` in this account/session) |
| Orchestration budget | `tokens: 16000`, `seconds: 90` (see Empirical Budget Adjustment below) |
| Version | Single version `VERSION$1`, `DEFAULT`/`FIRST`/`LAST` aliases all point to it |

### Empirical Budget Adjustment
Phase 6A's plan-time estimate of `seconds: 45` was validated against all 12
test questions. It was sufficient for structured-only, Search-only, and most
hybrid questions, but the flagship hybrid risk scenario (Test 9) consistently
exceeded 45 seconds across 3/3 attempts — `auto` orchestration selected
`claude-opus-4-8`, which issued ~12 structured SQL calls plus ~6 Search calls
(and, twice, an unsolicited platform `chart_instructions` server-skill
invocation) while gathering evidence for this multi-fact question, running
out of budget before completing synthesis. The time budget was raised to
`seconds: 90` based on this empirical evidence; no model was pinned — `auto`
remains in place exactly per the Phase 6A design.

## 3. Cortex Analyst Tool — `supply_chain_analytics`

| Property | Value |
|---|---|
| type | `cortex_analyst_text_to_sql` |
| semantic_view | `SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW` |
| execution_environment | warehouse `COMPUTE_WH`, `query_timeout: 60` |
| Authority | Sole source for Supplier OTD, Schedule Adherence, Fill Rate, inventory, demand, customer-order exposure, POs, shipments, supplier risk, lead-time metrics, landed cost, sourcing relationships |

## 4. Cortex Search Tool — `supplier_document_search`

| Property | Value |
|---|---|
| type | `cortex_search` |
| search_service | `SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH` |
| max_results | 5 |
| title_column | TITLE |
| id_column | DOCUMENT_ID |
| Filterable columns | SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE (matches deployed service ATTRIBUTES exactly — DOCUMENT_ID was NOT made filterable, consistent with the Phase 5 finding that it isn't a declared attribute on the underlying service) |
| Searchable column | SEARCH_TEXT |
| Returned/citation columns | DOCUMENT_ID, TITLE, SUPPLIER_ID, DOCUMENT_TYPE, SOURCE_REFERENCE, CONTENT |

**Citation behavior:** every document-backed claim is identified by `DOCUMENT_ID` + `DOCUMENT_TYPE` (e.g. "According to DOC000217 (SLA)…"), with `TITLE`/`SOURCE_REFERENCE` added when useful. Confirmed working correctly across all Search and hybrid tests.

## 5. Routing Rules (as implemented in agent instructions)

- **Structured only** → `supply_chain_analytics`. Never call Search merely because a supplier has documents.
- **Document only** → `supplier_document_search`. Never substitute document prose for current operational metrics.
- **Hybrid** → both tools; answer always separates "Current operational facts" from "Contractual/document evidence" — never merged into one number.
- **Lead-time scope rule**: DOC000017 (general/portfolio, 22 days) vs. DOC000217 (P104-specific SLA, 28 days) — P104-scoped questions prefer DOC000217; unscoped questions surface both without averaging.
- **No-hallucination rule**: if Search finds no supporting clause, state so explicitly; never answer from general knowledge.
- **Unsupported-metric rule**: Inventory Turnover — state unsupported, never approximate.
- **Currency rule**: never sum landed cost across currencies without governed FX data; ask for a currency or return a per-currency breakdown.

## 6. Agent Test Results (12/12 PASS)

| # | Question | Expected Routing | Observed Routing | Result |
|---|---|---|---|---|
| 1 | "What is our overall supplier OTD?" | Structured only | `system_execute_sql` via verified query, no Search call | **PASS** — 75.19% (0.751929) |
| 2 | "What is supplier S017's on-time delivery rate?" | Structured only | `system_execute_sql`, no Search call | **PASS** — 49.4% (0.493506) |
| 3 | "What is the current available inventory for P104 at P01?" | Structured only | Two-step latest-snapshot-date pattern via `system_execute_sql` | **PASS** — 8,200 units, 2026-08-15 |
| 4 | "What penalty applies if supplier S017 delivers P104 late?" | Search only | `supplier_document_search` only | **PASS** — DOC000217 (2%/wk, 10% cap) cited as governing for P104; DOC000017 (1.5%/wk general) noted separately, scopes not conflated |
| 5 | "What quality requirements are documented for supplier S017?" | Search only | `supplier_document_search` only | **PASS** — DOC000617/DOC000017 (97.5%) vs. DOC000217 (98%, P104-specific) vs. DOC000417 (scorecard) all cited, scopes distinguished |
| 6 | "What warranty period does S017's contract specify?" | Search only, no-hallucination | `supplier_document_search`, reviewed all 4 S017 docs | **PASS** — explicit "no warranty-period clause was found"; no duration invented |
| 7 | "How is supplier S017 performing against its contractual delivery commitments?" | Hybrid | Both tools | **PASS** — "Current operational facts" (49.4%) separated from "Contractual/document evidence" (92% portfolio / 95% P104 SLA); explicitly noted different scopes, not a contradiction |
| 8 | "What is the governed contract lead time for S017 supplying P104, and what does the SLA say?" | Hybrid, cross-check | Both tools, independent retrieval | **PASS** — Analyst 28 days = Search DOC000217 28 days; agent explicitly confirms they "agree exactly" |
| 9 | "What supply-chain risk from S017 threatens P104 customer deliveries, what is the exposure, and what contractual terms are relevant?" (flagship) | Hybrid | Both tools (~12 SQL + 6 Search calls) | **PASS** (after budget raised to 90s — see above). Structured facts: inventory 8,200/safety stock 3,000, 4 in-transit S017/P104 shipments (incl. PO900001 with a 5-day delay), risk category, open-order exposure. Document evidence: DOC000217/DOC000017/DOC000617/DOC000417. Full grounded answer delivered with sections clearly separated. Note: exposure total differed from the narrower Phase 4C VQ10 due-date-window baseline because the agent autonomously chose a broader "all open P104 orders" filter — valid independent retrieval, not a fabrication. |
| 10 | "What is happening with S017's delayed P104 shipment, and what does the contract say about expedited freight?" | Hybrid | Both tools | **PASS** — structured facts confirmed PO900001 promised 2026-08-25 / projected 2026-08-30 (5-day delay, matches flagship reference exactly); DOC000217 (4-day air lane, 2.6x rate, 50/50 split) and DOC000017 (general clause) cited as distinct scopes; no expedite action executed |
| 11 | "What is the total actual landed cost across all suppliers?" | Structured, governance | `supply_chain_analytics` only | **PASS** — all 11 currencies returned separately (matches VQ11 baseline); no single mixed-currency total; explicitly offered conversion only with governed FX data |
| 12 | "What is our inventory turnover?" | Structured, governance | No tool call needed | **PASS** — explicitly stated unsupported (no costed-inventory/COGS basis); offered valid alternatives; no proxy metric invented |

### Observations
- Orchestration `auto` consistently selected `claude-opus-4-8` for all 12 tests in this account/session.
- The platform's built-in `chart_instructions`/`server_skill` capability was invoked autonomously by the orchestrator on the flagship question (twice, across different runs) even though no charting tool was added to this Agent's `tools` list — this is a native platform capability, not a tool we configured, and it contributed to the Test 9 budget pressure.
- A trailing "I've reached the time limit... would you like me to continue?" line sometimes appears immediately after an already-complete substantive answer (observed on Test 9's third run) — this is a benign continuation-prompt artifact, not an indication that the preceding answer was incomplete.

## 7. Governance Confirmations

- **No-hallucination**: Test 6 — confirmed explicit "not found" behavior, no invented duration.
- **Currency governance**: Test 11 — confirmed no mixed-currency total; per-currency breakdown offered.
- **Unsupported-metric governance**: Test 12 — confirmed no Inventory Turnover approximation.
- **Scope-nuance governance**: Tests 4, 5, 7, 8 — confirmed general-contract vs. P104-SLA distinctions consistently preserved, never averaged or mislabeled as contradictions.
- **No action execution**: Test 10 — confirmed the agent discussed expedite terms without executing an expedite action.

## 8. Agent Versioning / Demo Readiness

`DESCRIBE AGENT` confirms a single version (`VERSION$1`) with `DEFAULT`, `FIRST`, and `LAST` aliases all pointing to it. All validation in this phase ran against this same default/live version — no separate draft/staging version was created, and none was necessary since `CREATE OR REPLACE AGENT` was used directly (per the Phase 6A-approved plan).

## 9. Files

- `docs/cortex_agent_design.md` (this file)
- `sql/13_cortex_agent.sql` — authoritative CREATE AGENT DDL (AGENTS schema + agent spec, including the empirical budget note)
- `sql/14_cortex_agent_validation.sql` — structural validation + 12-test DATA_AGENT_RUN catalog with recorded results

## 10. Regression (Phase 1–5, unchanged)

| Object | Status |
|---|---|
| 14 CURATED views | Unchanged |
| Semantic View structure | 12 tables / 15 relationships / 70 dimensions / 26 facts / 32 metrics / 15 Verified Queries — unchanged |
| Cortex Search Service | ACTIVE/ACTIVE, 139 source rows — unchanged |

No Phase 4 formal Cortex Analyst evaluation was re-run (the Semantic View was not modified in this phase).

## 11. Hackathon Compliance

Phase 6 remains fully Snowflake-native:
- Built entirely through the CoCo workflow (SQL DDL executed via CoCo, validated via CoCo).
- Cortex Agent orchestration (`SNOWFLAKE.CORTEX.DATA_AGENT_RUN`, `CREATE AGENT`).
- Cortex Analyst for structured analytics (`cortex_analyst_text_to_sql` tool over the governed Semantic View).
- Cortex Search for unstructured retrieval (`cortex_search` tool over the governed Search Service).
- No external orchestration framework, no external LLM gateway, no MCP, no third-party RAG service.
- The platform's built-in chart-generation capability (`chart_instructions`/`server_skill`) is a native Snowflake Cortex Agent runtime feature, not an externally introduced dependency.

**No hackathon eligibility concerns identified.**
