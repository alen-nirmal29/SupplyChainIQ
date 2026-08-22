# SupplyChainIQ — Entity Resolution Design & Implementation (Phase 8A)

Deterministic, read-only natural-language entity resolver that converts
supplier/part/plant business references (canonical ID, exact name,
normalized name, unique partial name, or fuzzy typo) into governed
canonical IDs — attached as a **fourth** tool to
`SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT`. Read-only, recommendation
supporting only; does not create, approve, or execute anything.

---

## 1. Master-Data Audit (actual, reconfirmed in Phase 8A)

| Entity | CURATED view | Canonical ID | Canonical name | Alternate source | Status field |
|---|---|---|---|---|---|
| Supplier | `CURATED.SUPPLIER` | `SUPPLIER_ID` | `SUPPLIER_NAME` | `SUPPLIER_NAME_PORTAL` (genuine 2nd source, 100/100 populated) | `VENDOR_STATUS` (`Active`/`Under Review`/`Inactive`) |
| Part | `CURATED.PART` | `PART_ID` | `PART_DESCRIPTION` | none | `ACTIVE_FLAG` (boolean) |
| Plant | `CURATED.PLANT` | `PLANT_ID` | `PLANT_NAME` | none | `ACTIVE_FLAG` (boolean) |

**Uniqueness findings:**
- Plant (12 rows): all names distinct, case-insensitively distinct, no nulls.
- Supplier (100 rows): all `SUPPLIER_NAME` values distinct (exact and CI), no nulls.
- Part (1000 rows): only **900 distinct** `PART_DESCRIPTION` values — **100 exact-duplicate-name groups** (pairs), e.g. `Seal Kit Type 318` → `P086` and `P986` (identical `PRODUCT_FAMILY`/`CATEGORY`/`CRITICALITY`).
- Supplier names follow `<Root> <Suffix>`; root words repeat **4×** each (e.g. "Pinnacle" → S017/S042/S067/S092; "Silverbrook", "Sterling" behave identically) — a single-token partial match is essentially never safe for suppliers.
- Part descriptions contain generic category phrases too (`"Seal Kit"` alone matches 54 parts).
- Plant names share `"Assembly Plant"` across 4 plants (P01, P05, P07, P09).
- `SUPPLIER_NAME_PORTAL` vs `SUPPLIER_NAME` differences across all 100 suppliers: 56 identical (case-insensitive), 20 whitespace-only, 20 punctuation-only (trailing period), **4 genuine semantic aliases** (`Ltd` ↔ `Limited`, e.g. S015/S030/S045).

**Flagship real names (confirmed from live data):**

| Entity | ID | Actual name |
|---|---|---|
| Supplier | S017 | **Pinnacle Industries** (China, APAC, Standard tier, Active) |
| Part | P104 | **High-Precision Hydraulic Control Valve Assembly Type 104** (Hydraulics/Valves, Critical) |
| Plant | P01 | **Pune Assembly Plant** (India, APAC) |

CUSTOMER/CARRIER resolution was audited (both `CURATED.CUSTOMER`/`CARRIER` exist) but **not implemented**: `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` has no customer/carrier parameter to resolve into, and Cortex Analyst already handles those names natively for analytics questions. Documented as a future extension only.

## 2. Fuzzy-Matching Experiments (empirical, `JAROWINKLER_SIMILARITY`, GA)

| Case | Input | Top score | Runner-up | Verdict |
|---|---|---|---|---|
| Minor typo | `Pinacle Industries` | S017 **94** | S076 Zenith Industries **84** | Clear gap |
| Vague word | `Assembly Plant` | P01 **81** | P07 **73** (4 plants contain the phrase) | Score-only would silently mis-resolve |
| Vague word | `Components` | S060 **78** | 7 suppliers 68–78 | No separation |
| Negative control | `Quantum Robotics Unlimited` | best of all 100 = **70** | — | Below any credible floor |

**Conclusion**: score alone is unsafe. A candidate-display floor of **80** was chosen and empirically validated: it captures the true typo match (94) and one legitimate near-neighbor (84) for `Pinacle Industries`, while showing **zero** candidates for the true negative control (best score 70). This is a **display floor only** — fuzzy results never auto-resolve (`CANONICAL_ID` stays `NULL`), matching the precision-over-recall goal.

## 3. Matching Ladder (deterministic, first-hit-wins, per entity type independently)

1. **EXACT_ID** — case-insensitive match against the canonical ID column.
2. **EXACT_NAME** — case-insensitive exact match against the canonical name (Supplier: `SUPPLIER_NAME` **OR** `SUPPLIER_NAME_PORTAL`, deduplicated by `SUPPLIER_ID`).
3. **NORMALIZED_EXACT** — after `TRIM`, collapsing repeated whitespace (`REGEXP_REPLACE ... '[[:space:]]+' ' '`), and stripping trailing `.`/`,` (`RTRIM(...,'.,')`). No semantic rewriting (`Ltd`↔`Limited` is never auto-normalized).
4. **UNIQUE_MATCH** — case-insensitive substring match (`LIKE '%ref%'`, reference ≥ 4 chars); accepted only if exactly one distinct canonical ID matches.
5. **FUZZY_CANDIDATES** — `JAROWINKLER_SIMILARITY` ranked, candidates with score ≥ 80 shown (top 5), **never auto-selected**.
6. **NO_MATCH** — nothing above the floor and no deterministic hit.

**Critical distinct-ID rule (mandatory at every automatically-resolving tier):** a tier only resolves automatically when it matches **exactly one distinct canonical ID**. If 2+ distinct IDs match at any tier (including exact tiers), the result is `AMBIGUOUS` at that tier — never "first row wins." Verified empirically: `"Seal Kit Type 318"` is an **exact** textual match to both `P086` and `P986` and correctly returns `AMBIGUOUS`, not a false `EXACT_NAME`.

## 4. Resolver Procedure

```sql
SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES(
  SUPPLIER_REFERENCE VARCHAR,   -- optional
  PART_REFERENCE VARCHAR,       -- optional
  PLANT_REFERENCE VARCHAR       -- optional
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
```

- Each of the three references is optional and independent; at least one must be supplied, or the procedure returns a graceful `{"REASON": "No entity references were supplied..."}` object.
- Reads only from `CURATED.SUPPLIER`, `CURATED.PART`, `CURATED.PLANT` — `SELECT` only, no writes of any kind.
- Returns exactly one row / one `VARIANT` value (single-cell), matching the same generic/procedure Cortex Agent tool convention proven in Phase 7B.

**Empirical implementation fix discovered in Phase 8A:** Snowflake does **not** guarantee lazy/short-circuit evaluation of correlated scalar subqueries inside `CASE WHEN` branches for this procedure body — a branch such as `WHEN C2 = 1 THEN ... (SELECT SUPPLIER_ID FROM tier2) ...` was found to raise `"Single-row subquery returns more than one row"` even when `C2 = 2` and that branch was not logically selected, because the engine evaluated the subquery for planning/optimization regardless of branch selection. **Fix:** every such scalar reference was rewritten as an aggregate (`(SELECT MAX(SUPPLIER_ID) FROM tier2)`), which always returns exactly one row/value regardless of how many rows the underlying tier CTE actually has, eliminating the error while leaving the resolution semantics unchanged (aggregate is only ever read when the branch it belongs to is genuinely selected, i.e., when the tier has exactly one row).

**Active-entity governance:** each resolved entity (any auto-resolving tier) includes a `STATUS_WARNING` field (non-null) when the matched Supplier's `VENDOR_STATUS <> 'Active'` or the matched Part/Plant's `ACTIVE_FLAG = FALSE`. The procedure still returns the canonical ID/name (it does not silently substitute a different, active entity) but flags the status so the Agent can surface the warning and avoid treating an inactive entity as equivalent to an active one.

## 5. Output Contract

Compact `VARIANT`; only requested entity sections are included (keys with `NULL` values are omitted by `OBJECT_CONSTRUCT` semantics — no need to prune manually). Example (flagship, all three requested):

```json
{
  "supplier": {"ENTITY_TYPE":"SUPPLIER","INPUT_REFERENCE":"Pinnacle Industries","RESOLUTION_STATUS":"EXACT_NAME","CANONICAL_ID":"S017","CANONICAL_NAME":"Pinnacle Industries","MATCH_METHOD":"EXACT_NAME_CI","CANDIDATE_COUNT":1,"CANDIDATES":[]},
  "part":     {"ENTITY_TYPE":"PART","INPUT_REFERENCE":"...","RESOLUTION_STATUS":"EXACT_NAME","CANONICAL_ID":"P104","CANONICAL_NAME":"...","MATCH_METHOD":"EXACT_NAME_CI","CANDIDATE_COUNT":1,"CANDIDATES":[]},
  "plant":    {"ENTITY_TYPE":"PLANT","INPUT_REFERENCE":"...","RESOLUTION_STATUS":"EXACT_NAME","CANONICAL_ID":"P01","CANONICAL_NAME":"...","MATCH_METHOD":"EXACT_NAME_CI","CANDIDATE_COUNT":1,"CANDIDATES":[]}
}
```

For `AMBIGUOUS`/`FUZZY_CANDIDATES`/`NO_MATCH`, `CANONICAL_ID`/`CANONICAL_NAME` are always `NULL` — never populated with the top candidate. `CANDIDATES` (max 5) include `CANONICAL_ID`, `CANONICAL_NAME`, `MATCH_SCORE` (fuzzy only), and one disambiguation field per entity type (Supplier: `REGION`/`VENDOR_STATUS`; Part: `PRODUCT_CATEGORY`/`CRITICALITY`; Plant: `REGION`/`COUNTRY`).

## 6. Fourth Agent Tool

```yaml
- tool_spec:
    type: "generic"
    name: "resolve_supply_chain_entities"
    description: "Authoritative deterministic resolver for converting supplier, part, and plant business references or canonical IDs into governed SupplyChainIQ canonical IDs..."
    input_schema:
      type: object
      properties:
        supplier_reference: {type: string, description: "..."}
        part_reference: {type: string, description: "..."}
        plant_reference: {type: string, description: "..."}
tool_resources:
  resolve_supply_chain_entities:
    identifier: "SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES"
    type: "procedure"
    execution_environment: {type: "warehouse", warehouse: "COMPUTE_WH", query_timeout: 60}
```

Parameter names (`supplier_reference`, `part_reference`, `plant_reference`) match the `input_schema` property names exactly, per the Phase 7B empirical parameter-name-matching requirement.

## 7. Agent Routing (orchestration instructions extended)

- Call `resolve_supply_chain_entities` whenever a supplier/part/plant is referenced by business name, description, partial name, alias, or mixed IDs/names.
- Clean canonical IDs (e.g. "S017"/"P104"/"P01") may be used directly without necessarily calling the resolver.
- Only call `evaluate_supply_chain_interventions` once every required entity has resolved to `EXACT_ID`, `EXACT_NAME`, `NORMALIZED_EXACT`, or `UNIQUE_MATCH`.
- **Never** call `evaluate_supply_chain_interventions` when any required entity is `AMBIGUOUS`, `FUZZY_CANDIDATES`, or `NO_MATCH` — surface the candidates/no-match explanation and stop.
- Do not overuse the resolver: pure analytics questions ("What is our overall supplier OTD?") stay on `supply_chain_analytics` only.
- Capability boundary extended: the Agent cannot schedule recurring monitoring, create automations, execute transfers/expedites/supplier switches, or create/update POs — must never offer these.

## 8. Direct Procedure Test Results (17/17 PASS)

| # | Test | Input | Result |
|---|---|---|---|
| 1 | Supplier exact ID | `S017` | `EXACT_ID` → S017/Pinnacle Industries |
| 2 | Part exact ID | `P104` | `EXACT_ID` |
| 3 | Plant exact ID | `P01` | `EXACT_ID` |
| 4–6 | Exact names (all 3) | Pinnacle Industries / High-Precision.../Pune Assembly Plant | all `EXACT_NAME` |
| 7 | Case-insensitive | `pinnacle industries` | `EXACT_NAME` |
| 8 | Punctuation normalization | `Pinnacle Industries.` | `NORMALIZED_EXACT` |
| 9–11 | Unique partial (all 3) | `Pinnacle Ind` / `Hydraulic Control Valve` / `Pune` | all `UNIQUE_MATCH`, single candidate |
| 12 | Ambiguous supplier partial | `Pinnacle` | `AMBIGUOUS`, 4 candidates (S017/S042/S067/S092) |
| 13 | Ambiguous exact-duplicate part | `Seal Kit Type 318` | `AMBIGUOUS`, 2 candidates (P086/P986) — proves exact-text duplicates do not auto-resolve |
| 14 | Ambiguous plant partial | `Assembly Plant` | `AMBIGUOUS`, 4 candidates (P01/P05/P07/P09) |
| 15 | No-match | `Quantum Robotics Unlimited` | `NO_MATCH` |
| 16 | Fuzzy typo | `Pinacle Industries` | `FUZZY_CANDIDATES`, top candidate S017 (score 94), `CANONICAL_ID = null` |
| 17 | Mixed ID + names | `S042` + part name + plant name | supplier `EXACT_ID`, part/plant `EXACT_NAME` |

All 17/17 PASS. All-null-input call returns a graceful `REASON` object, not an error.

## 9. Agent End-to-End Test Results (8/8 PASS)

| Test | Question shape | Result |
|---|---|---|
| A. Flagship natural language | Full business names for all 3 entities | resolver called → all `EXACT_NAME` → `evaluate_supply_chain_interventions('S017','P104','P01')` → same governed values as canonical-ID baseline (shortage 2150, Road expedite rank 1 recommended) |
| B. Canonical-ID flagship | "S017 P104 shortage at P01" | went directly to `evaluate_supply_chain_interventions` (resolver not required — IDs already clean); identical output values to Test A |
| C. Unique-partial flagship | "Hydraulic Control Valve... at Pune, ... Pinnacle Ind..." | resolver → all `UNIQUE_MATCH` → same intervention result |
| D. Mixed ID + names | "S042... High-Precision.../Pune Assembly Plant" | resolver → supplier `EXACT_ID`, part/plant `EXACT_NAME` → intervention tool called with S042/P104/P01 |
| E. Ambiguous supplier | "Can Pinnacle cover..." | resolver → `AMBIGUOUS` (4 candidates) → Agent asked to clarify → **intervention tool NOT called** |
| F. Ambiguous exact part | "...Seal Kit Type 318 part shortage..." | resolver → `AMBIGUOUS` (P086/P986) → Agent asked to clarify → **intervention tool NOT called** |
| G. Fuzzy typo | "...caused by Pinacle Industries?" | resolver → `FUZZY_CANDIDATES` (S017 top, score 94) → Agent asked for confirmation → **intervention tool NOT called** |
| H. No-match | "...caused by Quantum Robotics Unlimited..." | resolver → `NO_MATCH` → Agent explained and asked for a valid reference → **intervention tool NOT called** |

## 10. Canonical-vs-Natural-Language Parity

Test A (natural language) and Test B (canonical IDs) produced **identical** deterministic decision facts: shortage 2,150 units, `EXPEDITED_REPLENISHMENT` rank 1/recommended (Road, 3 days, arrives 2026-08-18), `INTERPLANT_TRANSFER` rank 2 (P03, cost not comparable), `ALTERNATE_SUPPLIER` rank 3 (S042, 926,650 INR), `EXPEDITE_CURRENT_SHIPMENT` rank 4/not feasible (SH900001). The Phase 7B governance-patch language (operational Road vs. contractual Air distinction, human-approval requirement) was present in both.

## 11. Phase 6/7 Regression (all PASS, unchanged)

- Overall Supplier OTD: **75.2%** (0.751929) — matches governed baseline; resolver correctly **not** called for this pure-analytics question.
- S017 OTD: **49.4%** (0.493506) — matches governed baseline.
- SLA penalty terms for S017 correctly cited from DOC000217 (2% per week, capped at 10%).
- Warranty negative control: correctly states no warranty clause found in any of the 4 S017 documents — no hallucination.
- Flagship intervention recommendation and the operational-Road-vs-contractual-Air governance distinction reproduced identically to the Phase 7B governance-patch baseline.

## 12. Phase 1–5 / Structural Regression

No source data, CURATED views, Semantic View, or Cortex Search Service were modified. Agent structure confirmed: exactly 4 project tools (`supply_chain_analytics`, `supplier_document_search`, `evaluate_supply_chain_interventions`, `resolve_supply_chain_entities`), single version (`VERSION$1`).

## 13. Privileges (EXECUTE AS CALLER)

| Privilege | On | Why |
|---|---|---|
| `USAGE` | `SUPPLYCHAINIQ_DB` | Namespace resolution |
| `USAGE` | `SUPPLYCHAINIQ_DB.DECISION` | To resolve/call the procedure |
| `USAGE` | `SUPPLYCHAINIQ_DB.CURATED` | Schema-level usage, not implied merely by object `SELECT` |
| `USAGE` | `COMPUTE_WH` | Execution environment |
| `SELECT` | `CURATED.SUPPLIER`, `CURATED.PART`, `CURATED.PLANT` | Resolver reads (caller's own role, since `EXECUTE AS CALLER`) |
| `USAGE` | `SUPPLYCHAINIQ_DB.DECISION.RESOLVE_SUPPLY_CHAIN_ENTITIES` | Direct/tool invocation |
| `USAGE` | `SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT` | To invoke the agent |
| Existing | All Phase 6/7 grants (semantic view, search service, `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS`, `CURATED` other views) | Unchanged |

## 14. Files

- `docs/entity_resolution_design.md` (this file)
- `sql/17_entity_resolution.sql` — resolver procedure DDL, full Agent redeploy (4 tools)
- `sql/18_entity_resolution_validation.sql` — structural validation, 17 direct-procedure tests, 8 Agent end-to-end tests, Phase 6/7 and Phase 1–5 regression

## 15. Hackathon Compliance

Snowflake-native throughout: CoCo-built, Cortex Agent + Cortex Analyst + Cortex Search + two GA custom tools (`type: generic`/`type: procedure`). `JAROWINKLER_SIMILARITY` is a documented GA SQL function (no Preview marker). No Agent Skills, no `code_execution` (Preview), no MCP, no external orchestration framework, no external entity-resolution API, no vector DB. No preview-feature dependency in the deployed design.
