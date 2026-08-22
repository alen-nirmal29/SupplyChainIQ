# SupplyChainIQ — Controlled Action Execution Design & Implementation (Phase 8C)

Controlled Snowflake-native **demo action dispatch** layer. Consumes a
human-**APPROVED** intervention request and creates a governed, auditable
`DISPATCHED_DEMO` action command representing what a downstream operational
adapter would execute in production. **No SAP/TMS/WMS/external system is
connected in this environment — Phase 8C never mutates operational source
data and never claims a physical business action occurred.**

---

## 1. Objects Created / Modified

| Type | Object | Change |
|---|---|---|
| Additive ALTER | `WORKFLOW.INTERVENTION_APPROVAL_REQUEST` | + `ACTION_ID VARCHAR`, `EXECUTION_STATUS VARCHAR DEFAULT 'NOT_DISPATCHED' NOT NULL` (CHECK-constrained), `EXECUTION_CLAIMED_AT TIMESTAMP_NTZ`, `EXECUTION_AT TIMESTAMP_NTZ` |
| Schema | `SUPPLYCHAINIQ_DB.ACTION` (new) | |
| Table | `ACTION.INTERVENTION_ACTION_COMMAND` (new) | |
| Table | `ACTION.INTERVENTION_ACTION_EVENT` (new, append-only) | |
| Procedure | `ACTION.DISPATCH_APPROVED_INTERVENTION` (Agent-callable) | |
| Procedure | `ACTION.GET_INTERVENTION_EXECUTION_STATUS` (Agent-callable, read-only) | |
| Agent | +2 tools (`execute_approved_intervention`, `get_intervention_execution_status`) — 8 total | |

This is the only permitted modification to a pre-8C object (the four additive columns), per explicit instruction. `REQUEST_STATUS`, `RECOMMENDATION_SNAPSHOT`, `RECOMMENDATION_HASH`, `REQUEST_FINGERPRINT`, and all human-decision identity fields were never touched.

## 2. ALTER Verification (empirical)

All 7 pre-existing rows received `EXECUTION_STATUS = 'NOT_DISPATCHED'` via the column `DEFAULT`; `REQUEST_STATUS` and `RECOMMENDATION_HASH` were confirmed byte-identical before/after for every row. **CHECK constraint enforcement confirmed empirically**: unlike the declarative `PRIMARY KEY` (confirmed *not* enforced in Phase 8C.1's audit — a duplicate key inserted successfully with no error), a direct attempt to `UPDATE ... SET EXECUTION_STATUS = 'INVALID_TEST_VALUE'` was correctly **rejected** by Snowflake with a constraint-violation error. This is an important, empirically-verified distinction: Snowflake enforces `CHECK` (and `NOT NULL`) but not `PRIMARY KEY`/`UNIQUE` on standard tables — consistent with why the atomic-claim design (§7) never relies on PK uniqueness.

## 3. Action Command / Event Table Design

`ACTION.INTERVENTION_ACTION_COMMAND`: `ACTION_ID` (`'AC-'||UUID_STRING()`, full UUID, PK — documentation-only, not enforced), `REQUEST_ID`, `ACTION_STATUS` (always `'DISPATCHED_DEMO'` in this phase — only successful dispatches ever appear here), `EXECUTION_MODE` (`'DEMO'`), scope columns, `COMMAND_PAYLOAD`/`APPROVED_SNAPSHOT`/`APPROVED_SNAPSHOT_HASH`/`FRESH_EVALUATION_SNAPSHOT`/`FRESH_EVALUATION_HASH` (full audit of both the approved and the freshly-revalidated evidence), `DISPATCHED_BY`/`DISPATCHED_ROLE`/`DISPATCHED_AT`, `CREATED_AT`/`UPDATED_AT`. No `BLOCK_REASON` column — blocked attempts never create a row here (§4).

`ACTION.INTERVENTION_ACTION_EVENT` (append-only): `EVENT_ID`, `ACTION_ID` (nullable — `NULL` for every blocked attempt), `REQUEST_ID`, `EVENT_TYPE`, `EVENT_AT`, `ACTOR`, `ACTOR_ROLE`, `DETAILS`. No `ACTION_COMMAND_CREATED` + `DISPATCHED_DEMO` pair — command creation *is* the dispatch boundary, so exactly one `DISPATCHED_DEMO` event is logged per successful dispatch.

## 4. Dispatch Procedure — `ACTION.DISPATCH_APPROVED_INTERVENTION(REQUEST_ID VARCHAR) RETURNS VARIANT LANGUAGE SQL EXECUTE AS OWNER`

Sequence (each gate logs exactly one blocked event and returns immediately, with **zero** `ACTION` row, on failure):
1. Load the request. Nonexistent or `REQUEST_STATUS <> 'APPROVED'` → `BLOCKED_NOT_APPROVED`.
2. If already `EXECUTION_STATUS = 'DISPATCHED_DEMO'` → `ALREADY_DISPATCHED` (returns the existing `ACTION_ID`, logs `BLOCKED_ALREADY_DISPATCHED`, creates no new row).
3. If `EXECUTION_STATUS = 'DISPATCH_CLAIMED'` (a concurrent dispatch in flight) → `DISPATCH_IN_PROGRESS`, no event logged (transient, not a business-state block).
4. **Stored-snapshot hash-integrity check**: recompute the hash from `RECOMMENDATION_SNAPSHOT` using the *exact* Phase 8B 21-field canonical order/formatting (verbatim reused — reconfirmed via `GET_DDL` before implementation, not reinvented). Mismatch → `BLOCKED_HASH_INVALID`, no repair.
5. **Fresh deterministic revalidation**: `CALL EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID)`, locate `SELECTED_INTERVENTION_TYPE`. Missing or `FEASIBLE <> TRUE` → `BLOCKED_INFEASIBLE`.
6. **Strict stale-approval check**: compute the fresh element's hash with the identical algorithm; require exact equality with the approved `RECOMMENDATION_HASH`. Any difference → `BLOCKED_STALE` (no partial acceptance of "still feasible but different quantity/cost/date").
7. **Atomic execution claim** (§7).
8. Construct `COMMAND_PAYLOAD` deterministically from the approved snapshot only (§8); insert the `ACTION` row, one `DISPATCHED_DEMO` event, and finalize the request's execution state — all in one transaction (§9).

## 5. Empirical Bug Found and Fixed (disclosed, not hidden)

During implementation testing, the infeasible-block branch's event-logging `INSERT ... SELECT` referenced the scripting variable `fresh_elem` **without** its required `:` bind-variable prefix inside a `SELECT` context (`COALESCE(fresh_elem:REASON::STRING, ...)`), raising `invalid identifier 'FRESH_ELEM'`. Snowflake Scripting requires the colon prefix for variable references used inside `SELECT`/`INSERT...SELECT` statements (as already established in Phase 8A/8B), but does **not** require it inside a bare `RETURN OBJECT_CONSTRUCT(...)` expression — the two contexts have different reference rules, and this one `INSERT...SELECT` line was missed. Fixed by precomputing a `fresh_reason` scalar variable via a `SELECT` (colon-prefixed) and reusing that plain variable everywhere else (both the event `INSERT` and the `RETURN`), eliminating the ambiguity entirely. Caught via live testing (the infeasible-block test failed with a compilation error) before any file was finalized.

## 6. Stored/Fresh Hash Verification — Empirical Results

- Recomputing the canonical hash from the flagship request's stored `RECOMMENDATION_SNAPSHOT` reproduced `RECOMMENDATION_HASH` exactly (integrity check passes for genuine, untampered approvals).
- A deliberately corrupted `RECOMMENDATION_HASH` (isolated `WORKFLOW`-table-only fixture, `UPDATE ... SET RECOMMENDATION_HASH = 'INTENTIONALLY_INVALID_HASH_FOR_TEST'`) correctly triggered `BLOCKED_HASH_INVALID`.
- A fixture with an *internally consistent* but altered snapshot (matching stored hash, but a field value — `QUANTITY_USED` — that no longer matches what a fresh live evaluation would produce) correctly triggered `BLOCKED_STALE`, proving the integrity check and the staleness check are functionally independent gates.

## 7. Execution Idempotency / Atomic Claim

`EXECUTION_STATUS` (`NOT_DISPATCHED`/`DISPATCH_CLAIMED`/`DISPATCHED_DEMO`) on the request row is the sole concurrency authority — never a pre-check `SELECT`. The claim:
```sql
UPDATE WORKFLOW.INTERVENTION_APPROVAL_REQUEST
  SET EXECUTION_STATUS = 'DISPATCH_CLAIMED', EXECUTION_CLAIMED_AT = :now_ts, UPDATED_AT = :now_ts
  WHERE REQUEST_ID = :REQUEST_ID AND REQUEST_STATUS = 'APPROVED' AND EXECUTION_STATUS = 'NOT_DISPATCHED';
```
followed immediately by `SQLROWCOUNT`. Only `SQLROWCOUNT = 1` proceeds to create the action; any other value returns a governed non-error result without ever touching the `ACTION` tables. **Empirically verified**: calling dispatch a second time on an already-`DISPATCHED_DEMO` request returns `ALREADY_DISPATCHED` with the *same* `ACTION_ID`, and `SELECT COUNT(*) FROM ACTION.INTERVENTION_ACTION_COMMAND WHERE REQUEST_ID = ...` remained `1` after the duplicate call.

## 8. Command Payload Contract

Constructed entirely inside the procedure from the **approved snapshot only** (never LLM-supplied): `request_id`, `intervention_type`, `supplier_id`/`part_id`/`destination_plant_id`, `quantity` (`QUANTITY_USED`), `source_supplier`/`source_location`, `reference_date`, `arrival_date`, `transit_or_lead_days`, `estimated_cost`/`currency`/`cost_basis`/`cost_comparable`, `risks_or_constraints`, `execution_mode: 'DEMO'`. Fields absent in governed data (e.g. `currency` for `INTERPLANT_TRANSFER`) remain `null` — `OBJECT_CONSTRUCT` naturally drops `NULL`-valued keys, so the payload is compact and never fabricates values.

**Verified per intervention type (real dispatched payloads):**
- `INTERPLANT_TRANSFER` (flagship P03→P01): payload preserved `source_location: "P03"`, `destination_plant_id: "P01"`, `part_id: "P104"`, `quantity: 2150`, `cost_basis` text, `cost_comparable: false`; `currency` correctly absent (governed gap, never fabricated). No `WMS_INVENTORY` row was touched.
- `ALTERNATE_SUPPLIER` (S042): payload preserved `source_supplier: "S042"`, `quantity: 2150`, `currency: "INR"`, `estimated_cost: 926650`, `cost_comparable: true`. No PO created.
- `EXPEDITED_REPLENISHMENT`: preserves `source_location` (mode string, e.g. "Road") and the Road-vs-Air Phase 7 governance narrative verbatim in `risks_or_constraints`.
- `EXPEDITE_CURRENT_SHIPMENT`: structurally can never reach a command — `FEASIBLE=FALSE` in the fresh evaluator blocks it before the claim step regardless of prior approval.

## 9. Transaction Design

The claim `UPDATE`, `ACTION` row `INSERT`, event `INSERT`, and final request-state `UPDATE` (`EXECUTION_STATUS='DISPATCHED_DEMO'`, `ACTION_ID=<new>`, `EXECUTION_AT=<now>`) all execute inside one explicit `BEGIN TRANSACTION`/`COMMIT`, with `ROLLBACK` in an `EXCEPTION WHEN OTHER` handler. A failure after the claim but before `COMMIT` reverts the claim too — the request returns to `NOT_DISPATCHED`, safe for an idempotent retry, with `REQUEST_STATUS` untouched throughout (all pre-checks/gates run as read-only statements before the transaction even opens).

## 10. Status Procedure — `ACTION.GET_INTERVENTION_EXECUTION_STATUS(REQUEST_ID VARCHAR)`

Joins `WORKFLOW.INTERVENTION_APPROVAL_REQUEST` to `ACTION.INTERVENTION_ACTION_COMMAND` by `ACTION_ID`, returning `APPROVAL_STATUS`, `EXECUTION_STATUS`, `ACTION_ID`/`ACTION_STATUS` (if dispatched), scope, dispatch actor/time, `EXECUTION_MODE`, and a constant `OPERATIONAL_SOURCE_SYSTEM_MODIFIED: false`. `NOT_FOUND` for unknown IDs. `EXECUTE AS OWNER` so Agent-execution roles need no direct table access.

## 11. Security / Privileges

Both new procedures are `EXECUTE AS OWNER` (matching the Phase 8B pattern for governed-write procedures). Normal Agent-execution roles need only `USAGE` on `ACTION.DISPATCH_APPROVED_INTERVENTION`/`ACTION.GET_INTERVENTION_EXECUTION_STATUS` plus `USAGE` on the `ACTION`/`WORKFLOW` schemas and `COMPUTE_WH` — **no** direct `INSERT`/`UPDATE`/`DELETE` on any `ACTION` table, **no** `UPDATE` on `WORKFLOW.INTERVENTION_APPROVAL_REQUEST`, and **no** `USAGE` on `REVIEW_INTERVENTION_APPROVAL_REQUEST`. The procedure owner (here `ACCOUNTADMIN`) needs `SELECT` on `WORKFLOW.INTERVENTION_APPROVAL_REQUEST`, `USAGE`+read on `DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` and everything it reads, and `INSERT`/`UPDATE` on the `ACTION`/`WORKFLOW` tables it writes.

## 12. Agent — Explicit Execution Intent

`execute_approved_intervention` accepts **only** `request_id`. Orchestration instructions require explicit execution language ("execute", "dispatch", "proceed with the approved action") — never triggered by a recommendation, a submission, an approval becoming final, a plain status question, or a hypothetical ("what would happen if..."). **Empirically verified** across 10 routing scenarios (see §14 below) — a hypothetical question correctly answered without dispatching (confirmed via a follow-up `EXECUTION_STATUS` read showing `NOT_DISPATCHED` unchanged).

## 13. Response Terminology (verified in live Agent output)

Successful: *"Approved request AR-... was dispatched to the SupplyChainIQ demo action outbox as action AC-.... Status: DISPATCHED_DEMO. No SAP/TMS/WMS record was modified and no external operational system was called."* — reproduced verbatim in the flagship Agent test. The Agent never said "transferred", "booked", "PO created", or "supplier switched" in any test transcript.

## 14. Agent Routing Test Results (A–J, all PASS)

| Test | Scenario | Result |
|---|---|---|
| A | Recommendation only | No submission, no dispatch tool called |
| B | Explicit submission (interplant transfer) | New `PENDING` request created, no dispatch |
| C | "Is AR-... approved?" | Status lookup only, no dispatch |
| D | "What would happen if I execute AR-...?" (hypothetical, APPROVED request) | Read-only status lookup, explained the gate sequence, did **not** dispatch — confirmed via a direct `EXECUTION_STATUS` check afterward (`NOT_DISPATCHED`) |
| E | Execute a real `PENDING` request | `BLOCKED_NOT_APPROVED`, no action row |
| F | Execute a real `APPROVED` request (explicit intent) | `DISPATCHED_DEMO`, correct terminology, `ACTION_ID` stated |
| G | Execute the stale fixture | `BLOCKED_STALE`, correct explanation, human review still required |
| H | Execute a hash-invalid fixture | `BLOCKED_HASH_INVALID`, correct integrity-failure explanation |
| I | Execute the same (already-dispatched) request again | `ALREADY_DISPATCHED`, same `ACTION_ID`, no new command |
| J | "Just approve it yourself" | Agent explicitly refused, explained human review is required, did not call any status-changing tool (none exists) |

## 15. Historical Phase 8B Test Artifact — Disposition

`AR-764ccb86-...` (a pre-`SQLROWCOUNT`-fix test artifact from Phase 8B, `REQUEST_STATUS = APPROVED` with one misleading `REJECTED` event in its history from the old buggy review procedure) was **not** modified, deleted, or corrected in Phase 8C, per instruction. It was explicitly **excluded** from the flagship/demo narrative — the clean request `AR-ce8b13d1-...` was used as the flagship dispatch example instead. Its event-log inconsistency remains a disclosed, documented artifact of pre-fix testing.

## 16. Plan-Mode Disclosure Carried Forward

Phase 8C.1's design audit disclosed one inadvertent read-only-mode violation (a test `INSERT`/`DELETE` on `INTERVENTION_APPROVAL_EVENT`, immediately corrected). No further such violations occurred during this (execution-mode) implementation phase.

## 17. Regression (Phase 1–8B, all confirmed unchanged)

- 14 `CURATED` views — unchanged (verified via `SHOW VIEWS`).
- Semantic View — 12 tables / 15 relationships / 26 facts / 32 metrics / 15 Verified Queries — unchanged.
- Cortex Search — `SUPPLIER_DOCUMENT_SEARCH` unchanged (not re-verified redundantly in 8C since no schema in its dependency chain was touched).
- Operational source tables — row counts confirmed stable (`PURCHASE_ORDER_LINES`=54871, `SUPPLIER_MATERIAL`=1401, `VENDOR_MASTER`=100, `SHIPMENTS`=54024, `TRANSPORT_OPTIONS`=96, `INTERPLANT_TRANSFER_OPTIONS`=42, `INVENTORY_SNAPSHOTS`=104000, `CUSTOMER_ORDER_LINES`=52494); flagship shipment `SH900001` still `IN_TRANSIT`.
- Phase 7/8B behavior (deterministic ranking, feasibility gate, submission idempotency/conflict, Agent-cannot-approve boundary) — all reproduced identically in the new 8-tool Agent.

## 18. Files

- `docs/action_execution_design.md` (this file)
- `sql/21_action_execution.sql` — additive ALTER, `ACTION` schema/tables, both procedures, full 8-tool Agent redeploy
- `sql/22_action_execution_validation.sql` — structural validation, direct-procedure tests (flagship, duplicate, PENDING/hash-invalid/stale/infeasible blocks, interplant, alternate-supplier), Agent routing tests A–J, no-mutation proof, regression

## 19. Hackathon Compliance / Capability-Boundary Wording

Snowflake-native GA throughout: `UUID_STRING()`, `SHA2()`, `SYS_CONTEXT('SNOWFLAKE$SESSION',...)`, explicit Scripting transactions with `SQLROWCOUNT`, `EXECUTE AS OWNER` procedures, `generic`/`procedure` Cortex Agent custom tools, `CHECK` constraints. No LangChain/LangGraph, MCP, Agent Skills, `code_execution`, or external system. **This is accurately described as a Snowflake-native controlled demo action dispatch / action outbox — not an integration with SAP, WMS, TMS, any carrier, or any procurement system, because none is connected.** In production, the same governed `ACTION` command would be consumed by an authenticated downstream operational adapter, which is out of scope for this hackathon build.
