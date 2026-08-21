# SupplyChainIQ — Intervention Decision Design (Phase 7)

Deterministic, read-only decision-support layer answering "what can we do
about this supply-chain risk, which interventions are feasible, what are the
trade-offs, and which should we recommend" — attached as a third tool to the
existing `SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT`. **Recommendation
only** — no business-action execution in this phase.

---

## 1. Data Audit (actual, reconfirmed in Phase 7B)

| Table | Grain | Key fields |
|---|---|---|
| `TMS_LOGISTICS.TRANSPORT_OPTIONS` (CURATED: `TRANSPORT_OPTION`) | region × plant × mode | `NORMAL_TRANSIT_DAYS`, `EXPEDITED_TRANSIT_DAYS`, `NORMAL_COST_FACTOR`, `EXPEDITE_COST_FACTOR`, `ACTIVE_FLAG` — **no currency column, no absolute cost** |
| `TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS` (CURATED: `INTERPLANT_TRANSFER_OPTION`) | plant × plant × mode | `TRANSIT_DAYS`, `COST_PER_UNIT`, `FIXED_TRANSFER_COST`, `MAX_TRANSFER_QTY`, `ACTIVE_FLAG` — **no currency column** |
| `SAP_ERP.SUPPLIER_MATERIAL` (CURATED: `SUPPLIER_PART`) | supplier × material | `AGREED_UNIT_PRICE`, `CONTRACT_LEAD_TIME_DAYS`, `MINIMUM_ORDER_QTY`, `MAX_WEEKLY_SUPPLY_QTY`, `CURRENCY` (governed), validity dates |
| `SAP_ERP.PURCHASE_ORDER_LINES` (CURATED: `PURCHASE_ORDER_LINE`) | PO×line | `PROMISED_DATE`, `PO_STATUS` |
| `TMS_LOGISTICS.SHIPMENTS` (CURATED: `SHIPMENT`) | shipment×line | `SHIPMENT_STATUS`, `TRANSPORT_MODE`, `PROJECTED_DELIVERY_DATE` |
| `WMS_INVENTORY.INVENTORY_SNAPSHOTS` (CURATED: `INVENTORY_SNAPSHOT`) | plant×part×date | `AVAILABLE_QTY`, `SAFETY_STOCK_QTY` |
| `CRM_ORDERS.CUSTOMER_ORDER_LINES` (CURATED: `CUSTOMER_ORDER_LINE`) | order×line | `DUE_DATE`, `ORDERED_QTY`, `FULFILLED_QTY`, `ORDER_VALUE` (INR only) |
| `PUBLIC.DATASET_METADATA` | 1 row | `DATASET_ANCHOR_DATE` (governed reference date) |

The procedure is built entirely on the **CURATED** layer (canonical
`SUPPLIER_ID`/`PART_ID`/`PLANT_ID` terminology, same layer the Semantic View
uses) rather than raw Phase‑1 source tables, for safe joins and consistency
with the rest of the project.

**Data gap (disclosed, not worked around):** neither `TRANSPORT_OPTION` nor
`INTERPLANT_TRANSFER_OPTION` has a currency column. Expedite cost is only a
*factor*; interplant-transfer cost fields (`COST_PER_UNIT`,
`FIXED_TRANSFER_COST`) have no governed currency. Both are handled per
Section 6.

## 2. Deterministic Reference Date

`SUPPLYCHAINIQ_DB.PUBLIC.DATASET_METADATA.DATASET_ANCHOR_DATE` (latest
`VERSION`) — **not** `CURRENT_DATE`. Confirmed value: **2026-08-15**. The
table's own `NOTES` column explicitly names S017/P104/P01 as this dataset's
flagship scenario, and this date matches the "latest snapshot" date used
throughout Phases 4–6.

## 3. Flagship Scenario — Recalculated Live

| Fact | Value |
|---|---|
| Available inventory (P104/P01) | 8,200 |
| Safety stock | 3,000 |
| Usable inventory | 5,200 |
| Near-term customer requirement (due within 14 days of reference date) | 7,350 units / ₹4,200,000 (3 order lines) |
| First affected customer due date | 2026-08-27 |
| Projected shortage | **2,150** |
| Delayed inbound shipment | SH900001, promised 2026-08-25, projected 2026-08-30 (**5-day delay**) |

The "near-term requirement" window (`REFERENCE_DATE` to `REFERENCE_DATE + 14
days`) mirrors the governed VQ10 due-date pattern from Phase 4 and
deterministically resolves to exactly the 3 flagship customer orders
(CO090001/2/3).

## 4. Three-Intervention Audit (live results)

**A. Expedite** — Two distinct sub-cases, deliberately not conflated:
- `EXPEDITE_CURRENT_SHIPMENT`: SH900001 is already `IN_TRANSIT` via Ocean. No structured field supports changing its mode/route — **always `FEASIBLE=false`**, explicit reason given, never silently omitted.
- `EXPEDITED_REPLENISHMENT`: a *new* order via the fastest **ACTIVE** expedited lane for the supplier's region → destination plant (`TRANSPORT_OPTION`). For S017 (APAC) → P01, structured data's fastest active lane is Road (3-day transit, 1.6× factor) — distinct from the SLA's contractually-approved Air lane (4-day, 2.6×); both are surfaced, never merged.

**B. Interplant transfer** — Only **P03** (of 5 candidate lane origins) actually stocks P104. Available=6,500, safety=2,500 → safely transferable=4,000 (covers the 2,150 shortage without breaching P03's safety stock). Lane P03→P01: Road, 3 days, $45/unit + $25,000 fixed, capacity 5,000.

**C. Alternate supplier** — S042 (Active, Preferred, non-primary) is the only approved alternate for P104: 7-day lead time, 4,500/week capacity, 431 INR/unit. **Currency differs from S017 (CNY)** — direct cost comparison is governed off.

## 5. Implementation Architecture Decision

Per current Snowflake docs (`cortex-agents-manage`, `cortex-agents-code-execution-tool`):

| Option | Verdict |
|---|---|
| Agent Skill (scripted) | Rejected — scripts execute via the `code_execution` tool, explicitly marked **Preview Feature — Open**; avoidable given a GA alternative exists |
| Custom tool (`type: generic`) + SQL UDF | Viable but a table UDF's control-flow is less natural for per-row feasibility/reason logic than a procedure |
| **Custom tool (`type: generic`) + stored procedure** | **Selected.** GA-documented (`type: procedure` shown in official docs), pure deterministic SQL (auditable via query history), no LLM math, read-only, Snowflake-native |
| Agent Skill + deterministic tools (hybrid) | Not needed — Phase 6 already proved plain agent orchestration instructions handle routing without a Skill object |

## 6. Two Empirical Integration Fixes (discovered via live testing)

1. **Parameter-name matching.** A `generic` tool backed by a `type: procedure`
   resource invokes the procedure using **named arguments matching the
   tool's `input_schema` property names exactly**. An initial version used
   prefixed parameter names (`P_SUPPLIER_ID`, etc.) and every call failed:
   *"named arguments ... do not match any signature"*. Fixed by renaming
   the procedure's parameters to `SUPPLIER_ID`, `PART_ID`,
   `DESTINATION_PLANT_ID` exactly.
2. **Single-cell result requirement.** The tool-calling convention expects
   **exactly one row, one column**: *"expected a single cell result set,
   got 4 rows and 22 columns"*. A `RETURNS TABLE(...)` procedure (4 rows) is
   therefore not callable this way. Fixed by changing the procedure to
   `RETURNS VARIANT` and packaging the same 4-row result as a single JSON
   array via `ARRAY_AGG(OBJECT_CONSTRUCT(...))` — the underlying
   calculation is unchanged, only the return-value packaging.

Both fixes are disclosed here and in `sql/15_intervention_decision_tools.sql` rather than silently patched.

## 7. Cost / Currency Governance (implemented exactly as designed)

| Intervention | `ESTIMATED_COST` | `CURRENCY` | `COST_COMPARABLE` | Basis |
|---|---|---|---|---|
| `EXPEDITE_CURRENT_SHIPMENT` | NULL | NULL | false | Not applicable — rerouting unsupported |
| `EXPEDITED_REPLENISHMENT` | NULL | NULL | false | Only a cost *factor* exists (`EXPEDITE_COST_FACTOR`); no governed absolute base freight cost — factor surfaced in `COST_BASIS` text, never fabricated into a currency amount |
| `INTERPLANT_TRANSFER` | Numeric (e.g. 121,750) | NULL | false | `quantity_used * COST_PER_UNIT + FIXED_TRANSFER_COST` is calculated, but `INTERPLANT_TRANSFER_OPTION` has **no governed currency attribute** — the number is returned as a magnitude only, explicitly never labeled with an assumed currency |
| `ALTERNATE_SUPPLIER` | Numeric (e.g. 926,650) | Governed (e.g. INR) | **true** | `quantity_used * AGREED_UNIT_PRICE` in `SUPPLIER_PART.CURRENCY` — a real, governed currency field |

**No cross-currency comparison is ever performed.** In the flagship
scenario, no two feasible options share a comparable currency, so cost was
correctly excluded from the ranking decision (see Section 8) — timing and
shortage coverage decided it instead.

## 8. Recommendation Algorithm (deterministic, computed by SQL, not the LLM)

`RANK() OVER (ORDER BY ...)` on:
1. `FEASIBLE` (true first)
2. Fully covers shortage (`SHORTAGE_AFTER = 0` first)
3. `ARRIVES_IN_TIME` (true first)
4. Lowest `SHORTAGE_AFTER`
5. Earliest `ARRIVAL_DATE`
6. Lowest comparable cost (only when `COST_COMPARABLE = true`)
7. `INTERVENTION_TYPE`, `SOURCE_LOCATION`, `SOURCE_SUPPLIER` (final deterministic tiebreakers)

`RECOMMENDED = TRUE` only when exactly one row holds rank 1 **and** is
feasible — ties or all-infeasible cases never produce a fabricated winner.

## 9. Decision Output Contract (implemented fields)

`INTERVENTION_TYPE, FEASIBLE, REASON, SOURCE_LOCATION, SOURCE_SUPPLIER, QUANTITY_AVAILABLE, QUANTITY_USED, SHORTAGE_BEFORE, SHORTAGE_AFTER, REFERENCE_DATE, ARRIVAL_DATE, FIRST_CUSTOMER_DUE_DATE, ARRIVES_IN_TIME, TRANSIT_OR_LEAD_DAYS, ESTIMATED_COST, CURRENCY, COST_BASIS, COST_COMPARABLE, RISKS_OR_CONSTRAINTS, EVIDENCE_SOURCE, RECOMMENDATION_RANK, RECOMMENDED` — every field present in the design plan; no field invented beyond what's derivable.

## 10. Agent Integration

Third tool `evaluate_supply_chain_interventions` (`type: generic`,
`input_schema` with `supplier_id`/`part_id`/`destination_plant_id`, backed by
`type: procedure` resource) added **alongside** the unchanged
`supply_chain_analytics` and `supplier_document_search` tools. Orchestration
instructions extended (not replaced) to route "what can we do", "compare
options", "recommend" questions to the new tool while keeping operational
metrics (Analyst) and contractual evidence (Search) as separate,
clearly-labeled sources — exactly as validated in the hybrid contract test
(Section 12).

## 11. Human-Approval Boundary

Explicit instruction: *"The Agent can EVALUATE and RECOMMEND intervention
options but CANNOT EXECUTE them: every operational intervention ... must
stop at RECOMMENDATION → HUMAN APPROVAL REQUIRED → NO EXECUTION CAPABILITY
IN THIS PHASE."* The procedure itself is `SELECT`-only — no
`INSERT`/`UPDATE`/`DELETE`/`MERGE`/`TRUNCATE`/`CREATE`-operational-record
anywhere in its body.

## 12. Test Results

### Direct procedure tests (pre-Agent)

| Test | Scenario | Result |
|---|---|---|
| Flagship | S017/P104/P01 | All 4 rows correct; EXPEDITED_REPLENISHMENT rank 1/recommended |
| Negative control (natural) | S099/P746/P11 (single-supplier part, no transfer candidate, expedite arrives late) | All 4 rows `FEASIBLE=false`; zero recommended — covers "no alt supplier," "no transfer lane," "expedite infeasible," and "all infeasible" simultaneously |
| Safety-stock protection (synthetic fixture) | available=0, safety=460 | `SAFE_TRANSFERABLE_QTY=0`, `QUANTITY_USED=0` — never breaches safety stock |
| Lane-capacity constraint (synthetic fixture) | available=8000, safety=2000, lane cap=500 | `QUANTITY_USED=500` (capacity-bound), `SHORTAGE_AFTER=1650` (genuine partial coverage) |

### Agent-level tests

| Test | Result |
|---|---|
| Flagship end-to-end | Tool called successfully first try; full grounded recommendation with rationale, cost-incomparability note, human-approval statement |
| Hybrid contract (decision + SLA) | Both tools used; explicitly reconciled structured tool's fastest-lane pick vs. SLA's contractually-approved lane as "different bases" — document text did not override feasibility |
| Phase 6 regression (5 spot checks: overall OTD, S017 OTD, penalty search, warranty negative control, OTD-vs-contractual hybrid) | All unchanged — intervention tool not invoked when not relevant |

## 13. Regression (Phase 1–6, unchanged)

14 CURATED views; Semantic View 12/15/70/26/32/15; Cortex Search
ACTIVE/ACTIVE/139 rows; all 5 spot-checked Phase 6 Agent behaviors identical.

## 14. Privileges

| Privilege | Object | Notes |
|---|---|---|
| `USAGE` | `SUPPLYCHAINIQ_DB`, `SUPPLYCHAINIQ_DB.DECISION` schema | To resolve/call the procedure |
| `USAGE` | `SUPPLYCHAINIQ_DB.AGENTS.SUPPLYCHAINIQ_AGENT` | To invoke the agent |
| `USAGE` | `COMPUTE_WH` | Execution environment for all 3 tools |
| `USAGE` | `SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` procedure | Direct/tool invocation |
| `SELECT` | `CURATED.INVENTORY_SNAPSHOT`, `CURATED.CUSTOMER_ORDER_LINE`, `CURATED.SHIPMENT`, `CURATED.PURCHASE_ORDER_LINE`, `CURATED.SUPPLIER`, `CURATED.SUPPLIER_PART`, `CURATED.TRANSPORT_OPTION`, `CURATED.INTERPLANT_TRANSFER_OPTION`, `PUBLIC.DATASET_METADATA` | The procedure is `EXECUTE AS CALLER` — the **caller's own role** needs these read grants, not just the procedure owner's. This is intentionally NOT relaxed to `EXECUTE AS OWNER` merely to simplify the demo. |
| Existing | Semantic View / Search Service grants | Unchanged from Phase 6 |

## 15. Files

- `docs/intervention_decision_design.md` (this file)
- `sql/15_intervention_decision_tools.sql` — DECISION schema, stored procedure, full Agent redeploy (3 tools)
- `sql/16_intervention_decision_validation.sql` — structural validation, direct-procedure tests, Agent-level tests, Phase 1–6 regression

## 16. Hackathon Compliance

Snowflake-native throughout: CoCo-built, Cortex Agent + Cortex Analyst +
Cortex Search + a GA custom tool (`type: generic` / `type: procedure`). No
Agent Skills, no `code_execution` (Preview), no MCP, no external
orchestration framework, no third-party LLM gateway. **No preview-feature
dependency in the deployed design.**

## 17. Governance Patch (post-Phase-7B clarification)

**Issue clarified:** the deterministic procedure's flagship expedited-
replenishment recommendation for S017/P104/P01 uses the fastest **ACTIVE**
structured lane, which happens to be **Road** (3 days). The SLA for the same
supplier/part (DOC000217) separately discusses an **approved expedited Air
lane** (4 days, 2.6× cost factor). Without an explicit instruction, the
Agent could imply these are the same authorized option — they are not.

**What changed:** only the Agent's `instructions.orchestration` text (Section
D of `sql/15_intervention_decision_tools.sql`). No change to:
- the stored procedure's SQL, ranking logic, or returned values (still
  Road, rank 1, RECOMMENDED = TRUE, identical output on re-test);
- the Semantic View, Cortex Search Service, or any source data;
- the tool count, tool_spec/tool_resources of any of the 3 tools;
- Phase 6 behavior.

**New rule added ("Operational-vs-contractual mode distinction"):** when the
tool's operationally preferred transport mode differs from the mode
discussed in contract/SLA evidence, the Agent must state (a) the
operationally preferred option, (b) the mode the SLA/contract discusses,
(c) that contractual approval/cost-sharing for the operational option has
not been established from the available documents, and (d) that human
approval and contract verification are required before execution — without
altering the deterministic ranking.

**Re-validation (both passed, deterministic values unchanged across
before/after runs):**
- Flagship recommendation test ("What can we do about the S017 P104 shortage
  at P01? What do you recommend and why?") — response now includes an
  explicit "Operational vs. contractual mode note" separating the Road
  recommendation from the SLA's Air lane, and states contractual approval
  for Road has not been established.
- Hybrid SLA consistency test ("...is the recommended intervention
  consistent with the contractually approved expedite lane?") — response
  states plainly "No — ... not the same lane", contrasts Road (3d, 1.6×)
  vs. Air (4d, 2.6×), and requires human approval/contract verification
  before action. Does not claim DOC000217 authorizes the Road option.
