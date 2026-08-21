# SupplyChainIQ — Cortex Search Design (Phase 5)

Governed unstructured-evidence retrieval layer over the supplier-document
corpus. Structured analytics remain exclusively in
`SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW` (Cortex Analyst).
Cortex Search is used ONLY for document/evidence retrieval and does not
duplicate any structured metric, dimension, or fact.

---

## 1. Phase 5A Source Audit (reconfirmed in Phase 5B)

Source: `SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS`

| Property | Value |
|---|---|
| Row count | 139 |
| DOCUMENT_ID | 139/139 non-null, 139/139 distinct (unique) |
| CONTENT | 139/139 non-null |
| Columns | DOCUMENT_ID, SUPPLIER_ID, DOCUMENT_TYPE, TITLE, EFFECTIVE_DATE, EXPIRY_DATE, CONTENT, SOURCE_REFERENCE, CREATED_AT |
| SUPPLIER_ID nulls | 5 (Procurement Policy x3, Logistics Policy x2 — company-wide policy docs, not supplier-specific) |
| Distinct suppliers | 100 (S001–S100) |
| Document types | Supplier Contract (100), SLA (20), Supplier Scorecard Narrative (10), Quality Agreement (4), Procurement Policy (3), Logistics Policy (2) |
| CONTENT length | min 670, max 3037, avg 2480, median 2984 characters |
| Retention (pre-creation) | `DATA_RETENTION_TIME_IN_DAYS = 1` |
| Change tracking (pre-creation) | `OFF` |
| Change tracking (post Search-Service-creation) | `ON` — see Section 5 |

**Document-coverage limitation:** not every supplier has every document type.
Only the 100 Supplier Contracts cover all suppliers; SLA (20 suppliers),
Scorecard Narrative (10 suppliers), and Quality Agreement (4 suppliers) exist
only for an enriched subset. **S017 is one of the fully-enriched suppliers**
(has all 4 supplier-specific types) — this is why it is the flagship demo
supplier. For most other suppliers, "no SLA found" is expected and correct,
not a retrieval failure.

## 2. Whole-Document Indexing Rationale

Max CONTENT length is 3037 characters (~600 tokens) — well under any
single-pass embedding limit. No chunk table, external embedding store, or
vector database was created. One search row = one source document row.

## 3. S017 Flagship Evidence Catalog (verified, not invented)

| DOCUMENT_ID | Type | Key terms confirmed present |
|---|---|---|
| DOC000017 | Supplier Contract | OTD ≥92%, lead time 22 days (portfolio-wide), quality ≥97.5%, penalty 1.5%/week service credit, escalation (24h / 5 business days), expedite cost-sharing |
| DOC000217 | SLA | **P104-specific**: lead time **28 days** (7 production + 21 ocean transit), OTD ≥95%, quality ≥98%, penalty 2%/week capped at 10%, expedite air-freight 2.6x rate / 50-50 cost split, escalation (24h / Supply Continuity Council within 48h) |
| DOC000417 | Supplier Scorecard Narrative | Narrative restating 92%/22-day/97.5% targets; risk-escalation guidance |
| DOC000617 | Quality Agreement | Acceptance ≥97.5%, containment/CAPA timelines (24h/3 days/10 days), escalation to Quality Council |

The 22-day (portfolio) vs. 28-day (P104-specific) lead-time figures are a
genuine, intentional document nuance — not a data error. This matches the
governed Phase 4 baseline: `supplier_part.contract_lead_time_days_avg` for
S017/P104 = 28 (drawn from the P104-scoped SLA, not the general contract).

**Verified-absent terms (negative-control basis):** "warranty" and
"indemnif*" appear 0 times across all 139 documents.

## 4. Search Architecture

- No chunk table. `SEARCH_TEXT` is a deterministic inline projection computed
  only inside the Cortex Search Service's own `AS` query:
  `'Title: ' || TITLE || '\nDocument Type: ' || DOCUMENT_TYPE || '\n\n' || CONTENT`
- `TITLE` and `CONTENT` remain available as separate returned columns for citation.
- Search-row schema:

| Field | Classification |
|---|---|
| DOCUMENT_ID | Primary key (TEXT, 139/139 unique) |
| SUPPLIER_ID | Filterable attribute (nullable) |
| DOCUMENT_TYPE | Filterable attribute |
| TITLE | Returned metadata |
| EFFECTIVE_DATE / EXPIRY_DATE | Filterable attribute + returned metadata |
| SOURCE_REFERENCE | Returned metadata (citation) |
| CONTENT | Returned metadata (citation source text) |
| SEARCH_TEXT | Searchable text (indexed column only — not a citation field) |

## 5. Deployed Service Configuration

```sql
CREATE OR REPLACE CORTEX SEARCH SERVICE SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH
  ON SEARCH_TEXT
  PRIMARY KEY (DOCUMENT_ID)
  ATTRIBUTES SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '12 hours'
  REFRESH_MODE = INCREMENTAL
  INITIALIZE = ON_CREATE
AS
SELECT DOCUMENT_ID, SUPPLIER_ID, DOCUMENT_TYPE, TITLE, EFFECTIVE_DATE, EXPIRY_DATE,
       SOURCE_REFERENCE, CONTENT,
       ('Title: ' || TITLE || '\nDocument Type: ' || DOCUMENT_TYPE || '\n\n' || CONTENT) AS SEARCH_TEXT
FROM SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS;
```

All requested clauses (`PRIMARY KEY`, `REFRESH_MODE = INCREMENTAL`,
`INITIALIZE = ON_CREATE`) were accepted by this account's deployed syntax —
no fallback to a reduced clause set was required.

**Post-creation structural state (`DESCRIBE CORTEX SEARCH SERVICE`):**

| Property | Value |
|---|---|
| search_column | SEARCH_TEXT |
| primary_key_columns | DOCUMENT_ID |
| attribute_columns | SUPPLIER_ID, DOCUMENT_TYPE, EFFECTIVE_DATE, EXPIRY_DATE |
| warehouse | COMPUTE_WH |
| target_lag | 12 hours |
| refresh_mode | INCREMENTAL |
| source_data_num_rows | 139 |
| indexing_state | ACTIVE |
| indexing_error | (empty — healthy) |
| serving_state | ACTIVE |
| embedding_model | **snowflake-arctic-embed-m-v1.5** (Snowflake-selected default; no custom model was specified) |
| auto_suspend | NULL (not set, per Phase 5 baseline) |

**Disclosed source-table side effect:** creating the service with
`REFRESH_MODE = INCREMENTAL` caused Snowflake to automatically enable
`CHANGE_TRACKING` on the underlying source table
`SUPPLYCHAINIQ_DB.DOCUMENTS.SUPPLIER_DOCUMENTS` (observed: `OFF` → `ON`).
This is a metadata-only side effect required for incremental refresh — no
document rows were modified and `DATA_RETENTION_TIME_IN_DAYS` was unchanged
(remained 1). This is disclosed explicitly; the source object is **not**
claimed to be entirely untouched.

## 6. Privileges / Cost

- Role: `ACCOUNTADMIN` — owns `SUPPLYCHAINIQ_DB` (implies `CREATE SCHEMA` /
  `CREATE CORTEX SEARCH SERVICE`), owns `COMPUTE_WH` (implies `USAGE`).
- `SNOWFLAKE.CORTEX_USER` database role: granted to `ACCOUNTADMIN` and `PUBLIC`.
- No new warehouse created; existing `COMPUTE_WH` (X-Small) reused.
- 139 rows, whole-document indexing → trivial index-build cost.
- No external vector store or third-party RAG service used.

## 7. Document Retrieval Quality Summary (10 core tests)

| # | Query | Filter | Top Document IDs | Expected Doc(s) | Expected Rank | Result | Notes |
|---|---|---|---|---|---|---|---|
| 1 | "What SLA commitments exist for supplier S017?" | SUPPLIER_ID='S017' | DOC000217, DOC000017, DOC000417, DOC000617 | DOC000217 | Top 1–3 | **PASS** | DOC000217 ranked #1 (reranker 1.79); confirmed 28-day/95%/98% terms present in CONTENT |
| 2 | "What contractual lead-time obligation is documented for S017?" | SUPPLIER_ID='S017' | DOC000017, DOC000217, DOC000417, DOC000617 | DOC000017 (22d) + DOC000217 (28d) | Both in top 2–4 | **PASS** | Both distinct lead-time figures retrievable; not treated as a contradiction |
| 3 | "What delivery performance percentage must S017 maintain?" | SUPPLIER_ID='S017' | DOC000017, DOC000417, DOC000617, DOC000217 | 92% (contract) + 95% (SLA) | Both in returned set | **PASS** | All 4 S017 docs returned (small corpus); both percentages present |
| 4 | "What quality acceptance rate is required from S017?" | SUPPLIER_ID='S017' | DOC000617, DOC000417, DOC000017, DOC000217 | 97.5% (Quality Agmt) + 98% (SLA) | Both in top 4 | **PASS** | DOC000617 ranked #1; DOC000217 (98%) present |
| 5 | "What penalty applies if S017 delivers late?" | SUPPLIER_ID='S017' | DOC000217, DOC000017, DOC000417, DOC000617 | DOC000217 (2%/wk) + DOC000017 (1.5%/wk) | At least 1 strong, both in top 5 | **PASS** | Both in top 2 of 4 |
| 6 | "supplier contract terms" | SUPPLIER_ID='S042' | DOC000042, DOC000242, DOC000642, DOC000442 | All S042-only | 100% isolation | **PASS** | Zero S017 (or any other supplier) leakage — filter isolation confirmed |
| 7 | "logistics expedite mode selection policy" | DOCUMENT_TYPE='Logistics Policy' | DOC000904, DOC000905 | DOC000904, DOC000905 | Exactly these 2 | **PASS** | SUPPLIER_ID null on both, as expected |
| 8 | "escalation twenty-four hours Supply Continuity Council" | SUPPLIER_ID='S017' | DOC000017, DOC000217, DOC000617, DOC000417 | DOC000217 | Ranks highly | **PASS** | DOC000217 rank #2 of 4 by blended score, but has dominant text_match (0.052 vs ~3e-7 others) — the literal phrase is concentrated there |
| 9 | "If Pinnacle Industries ships late for the hydraulic valve part, what happens?" | none | DOC000217, DOC000017, DOC000092, DOC000042, DOC000067 | DOC000217 | Top result, no exact-keyword requirement | **PASS** | DOC000217 ranked #1 of 5 via semantic match |
| 10 | "What warranty period does S017's contract specify?" | SUPPLIER_ID='S017' | DOC000017, DOC000217, DOC000617, DOC000417 | None (negative control) | N/A | **PASS** | Retrieval still returns ranked documents (expected — Cortex Search does not refuse); verified none contain "warranty" anywhere in CONTENT. Recorded as "no supporting evidence found in returned corpus," not a search failure |

### Additional structural tests

- **Date-range attribute filter** (`EFFECTIVE_DATE @gte 2025-09-01 AND @lte 2025-09-30`): 10 rows returned, all within range. **PASS** — date-range filtering confirmed supported.
- **Primary-key filter (finding, not a failure):** `DOCUMENT_ID` was declared as `PRIMARY KEY` but not also as an `ATTRIBUTES` column. Direct `@eq` filtering on `DOCUMENT_ID` fails with error `399114` ("Invalid filter query: Column DOCUMENT_ID does not exist as a filter"). This is a real constraint of the current (approved) `ATTRIBUTES` list and is disclosed rather than silently worked around. A practical PK-equivalent lookup was demonstrated instead: a compound filter (`SUPPLIER_ID='S017' AND DOCUMENT_TYPE='SLA'`) uniquely resolves to exactly `DOC000217`. If direct `DOCUMENT_ID`-based filtering is required in a future phase, `DOCUMENT_ID` would need to also be added to `ATTRIBUTES` (not done in this phase, since it would deviate from the approved design without explicit re-approval).

## 8. Agent-Readiness (Phase 6 preparation — no Agent created in this phase)

| Config | Value |
|---|---|
| Tool name | `supplier_document_search` |
| Service | `SUPPLYCHAINIQ_DB.SEARCH.SUPPLIER_DOCUMENT_SEARCH` |
| Title column | `TITLE` |
| ID column | `DOCUMENT_ID` |
| Search column | `SEARCH_TEXT` |
| Filterable columns | `SUPPLIER_ID`, `DOCUMENT_TYPE`, `EFFECTIVE_DATE`, `EXPIRY_DATE` |
| Max results | 5 |
| Returned evidence fields | `DOCUMENT_ID`, `TITLE`, `DOCUMENT_TYPE`, `SUPPLIER_ID`, `SOURCE_REFERENCE`, `CONTENT` |

**Critical future-agent rule (no-hallucination):** If retrieved documents do
not contain supporting evidence for a requested contractual term, the Agent
must explicitly say no supporting clause was found rather than inventing one.
This rule is directly evidenced by Test 10 above: the search service returns
ranked (but non-supporting) documents for the warranty query, and the correct
downstream behavior is an explicit "not found" statement, not a fabricated
answer.

## 9. Files

- `docs/cortex_search_design.md` (this file)
- `sql/10_document_search_source.sql` — source audit + SEARCH schema creation
- `sql/11_cortex_search_service.sql` — authoritative CREATE CORTEX SEARCH SERVICE DDL
- `sql/12_cortex_search_validation.sql` — structural validation + 10-test retrieval catalog + date/PK filter tests

## 10. Structured-Model Regression (Phase 1–4, unchanged)

Re-verified after Phase 5B: 14 CURATED views, 12 logical tables / 15
relationships / 70 dimensions / 26 facts / 32 metrics / 15 Verified Queries
in `SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW` all unchanged. No
Cortex Analyst evaluation was re-run (nothing in the Semantic View changed).
