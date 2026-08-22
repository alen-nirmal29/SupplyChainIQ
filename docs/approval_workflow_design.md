# SupplyChainIQ — Human Approval Workflow Design & Implementation (Phase 8B)

Governed, human-in-the-loop approval workflow for supply-chain intervention
recommendations. Recommendation -> Approval Request -> Human Decision
(Approved/Rejected/Cancelled). **No operational execution occurs in this
phase, at any status.**

---

## 1. Objects Created

| Type | Object |
|---|---|
| Schema | `SUPPLYCHAINIQ_DB.WORKFLOW` |
| Table | `WORKFLOW.INTERVENTION_APPROVAL_REQUEST` (current-state row per request) |
| Table | `WORKFLOW.INTERVENTION_APPROVAL_EVENT` (append-only audit trail) |
| Procedure | `WORKFLOW.SUBMIT_INTERVENTION_FOR_APPROVAL` (Agent-callable) |
| Procedure | `WORKFLOW.REVIEW_INTERVENTION_APPROVAL_REQUEST` (**human-only, never an Agent tool**) |
| Procedure | `WORKFLOW.GET_INTERVENTION_APPROVAL_STATUS` (Agent-callable, read-only) |
| Agent tool (5th) | `submit_intervention_for_approval` |
| Agent tool (6th) | `get_intervention_approval_status` |

No Phase 1–8A object was modified.

## 2. Request / Event Table Schemas

`INTERVENTION_APPROVAL_REQUEST`: `REQUEST_ID` (PK, full UUID, `'AR-'||UUID_STRING()` — never truncated), `REQUEST_STATUS`, `SUPPLIER_ID`/`PART_ID`/`DESTINATION_PLANT_ID`, `SELECTED_INTERVENTION_TYPE`, `RECOMMENDATION_RANK`, `RECOMMENDATION_SNAPSHOT` (VARIANT), `RECOMMENDATION_HASH`, `REQUEST_FINGERPRINT`, `DATASET_REFERENCE_DATE`, `REQUESTED_BY`/`REQUESTED_ROLE`/`REQUESTED_AT`, `APPROVED_OR_REJECTED_BY`/`APPROVER_ROLE`/`DECISION_AT`/`DECISION_COMMENT`, `CREATED_AT`/`UPDATED_AT`. No operational-execution fields exist.

`INTERVENTION_APPROVAL_EVENT` (append-only, never `UPDATE`d/`DELETE`d by any procedure): `EVENT_ID`, `REQUEST_ID`, `EVENT_TYPE` (`REQUEST_CREATED`/`APPROVED`/`REJECTED`/`CANCELLED`), `EVENT_AT`, `ACTOR`, `ACTOR_ROLE`, `OLD_STATUS`, `NEW_STATUS`, `COMMENT`.

## 3. Canonical Snapshot Hash — Fixed Field Order (reproducible by Phase 8C)

`RECOMMENDATION_HASH = SHA2(canonical_string, 256)` where `canonical_string` is the `|`-joined, NULL-safe (`COALESCE(..., 'NULL')`) concatenation of, **in this exact order**:

```
SUPPLIER_ID | PART_ID | DESTINATION_PLANT_ID | INTERVENTION_TYPE | FEASIBLE |
SOURCE_LOCATION | SOURCE_SUPPLIER | QUANTITY_AVAILABLE | QUANTITY_USED |
SHORTAGE_BEFORE | SHORTAGE_AFTER | REFERENCE_DATE | ARRIVAL_DATE |
FIRST_CUSTOMER_DUE_DATE | ARRIVES_IN_TIME | TRANSIT_OR_LEAD_DAYS |
ESTIMATED_COST | CURRENCY | COST_BASIS | COST_COMPARABLE |
RISKS_OR_CONSTRAINTS | EVIDENCE_SOURCE | RECOMMENDATION_RANK | RECOMMENDED
```

Booleans/numbers/dates are cast via `TO_VARCHAR` before concatenation for deterministic formatting (avoids VARIANT-vs-typed ambiguity). **Empirically verified reproducible**: independently recomputing this exact expression from the stored `RECOMMENDATION_SNAPSHOT` on a live request reproduced the stored `RECOMMENDATION_HASH` exactly (`HASH_MATCHES = TRUE`).

## 4. Request Fingerprint / Idempotency

`REQUEST_FINGERPRINT = SHA2(SUPPLIER_ID||'|'||PART_ID||'|'||DESTINATION_PLANT_ID||'|'||SELECTED_INTERVENTION_TYPE||'|'||RECOMMENDATION_HASH||'|'||REQUESTED_BY, 256)`.

On submission, `SUBMIT_INTERVENTION_FOR_APPROVAL` checks for an existing `PENDING` row with the same `(SUPPLIER_ID, PART_ID, DESTINATION_PLANT_ID, SELECTED_INTERVENTION_TYPE)`:

- **Fingerprint matches** (identical requester + identical evidence) -> return the **same existing** `REQUEST_ID`; no new row, no new event (empirically verified: an exact-duplicate resubmission returned the original `REQUEST_ID` with zero new rows).
- **Fingerprint differs but `RECOMMENDATION_HASH` also differs** (evidence has changed since the pending request was created) -> `STATUS = CONFLICT`; the existing stale request is neither silently reused nor duplicated — the caller is told to review/cancel it first (empirically verified using an isolated test-fixture hash/fingerprint override on a *workflow*-table row only — no source data was touched).
- **Fingerprint differs but `RECOMMENDATION_HASH` matches** (same evidence, different requester) -> return the existing `PENDING` request rather than creating a second parallel one for unchanged evidence.
- **No matching-scope `PENDING` row exists** (fresh, or the only prior request(s) are terminal) -> create a new request (empirically verified: after a request for `S017/P104/P01/EXPEDITED_REPLENISHMENT` reached a terminal state, resubmitting the same scope+type created a genuinely new, distinct `REQUEST_ID`).

## 5. Invoking-Session Identity Mechanism

`REQUESTED_BY`/`REQUESTED_ROLE` and `APPROVED_OR_REJECTED_BY`/`APPROVER_ROLE` are captured via `SYS_CONTEXT('SNOWFLAKE$SESSION','PRINCIPAL_NAME')` / `SYS_CONTEXT('SNOWFLAKE$SESSION','ROLE')`, per the corrected instruction (not assumed equivalent to `CURRENT_USER()`/`CURRENT_ROLE()` without verification).

**Empirical result:** tested directly via plain SQL and inside an `EXECUTE AS OWNER` procedure — both `SYS_CONTEXT('SNOWFLAKE$SESSION',...)` and `CURRENT_USER()`/`CURRENT_ROLE()` returned identical values (`ALEN`/`ACCOUNTADMIN`) with **no additional grant required** beyond the ACCOUNTADMIN role already held. No `READ SESSION`-style privilege error was encountered. Because this environment has only one real identity, this test **cannot prove** whether the two mechanisms would diverge under owner-rights execution invoked by a genuinely different caller role — documented as an open item, not claimed as fully proven. `SYS_CONTEXT('SNOWFLAKE$SESSION',...)` is used as the primary mechanism per the instruction, since Snowflake documents it as reading live session attributes of the actual invoking session regardless of rights model, which is the more conservative choice.

## 6. Procedure Rights

| Procedure | Rights | Why |
|---|---|---|
| `SUBMIT_INTERVENTION_FOR_APPROVAL` | `EXECUTE AS OWNER` | Writes to governed workflow tables; callers need only `USAGE` on the procedure, not direct table `INSERT` rights — narrower than Phase 7's blanket `CALLER` choice, deliberately, because this procedure performs governed writes Phase 7's read-only procedure did not. |
| `REVIEW_INTERVENTION_APPROVAL_REQUEST` | `EXECUTE AS OWNER` | Same reasoning — the only procedure that changes request status must have write access funneled exclusively through it. |
| `GET_INTERVENTION_APPROVAL_STATUS` | `EXECUTE AS OWNER` | Pure read, but owner-rights mediation means Agent-execution roles need no direct `SELECT` on the workflow tables at all — least additional privilege for normal callers. |

**Nested owner/caller-rights behavior (empirically tested and confirmed):** `SUBMIT_INTERVENTION_FOR_APPROVAL` (`OWNER` rights) successfully calls `SUPPLYCHAINIQ_DB.DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` (`CALLER` rights) via `eval_result := (CALL proc(args))` syntax (a bare function-style call, e.g. `proc(args)`, is **not** valid for stored procedures — confirmed by an explicit compilation error; the parenthesized `CALL` expression is required). Because both procedures are owned by `ACCOUNTADMIN` in this environment, the nested call succeeded without any additional grant. **Documented for production**: if a lower-privileged role owned `SUBMIT_INTERVENTION_FOR_APPROVAL`, that owner role would need `SELECT` on all `CURATED` views the evaluator reads and `USAGE` on `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS`, since a caller-rights inner procedure invoked from within an owner-rights outer procedure executes with the outer procedure's active (owner) role, not the original session's role.

**Technical implementation notes discovered during build:**
- VARIANT-path expressions (e.g. `:variable:FIELD::TYPE`) cannot be used directly inside an `INSERT ... VALUES (...)` list (raises `"Invalid expression [...] in VALUES clause"`); fixed by using `INSERT ... SELECT ...` instead, and by precomputing scalar values (`rec_rank`, `ref_dt`, etc.) into local variables before use in any `VALUES`/`SELECT` list.
- `IF (x IS NOT TRUE)` is not valid Snowflake Scripting syntax combined directly with a variant-derived boolean; replaced with `IF (NOT COALESCE(x, FALSE))`.

## 7. Feasibility Gate (re-derivation, never trusts the caller)

`SUBMIT_INTERVENTION_FOR_APPROVAL` accepts only `supplier_id`, `part_id`, `destination_plant_id`, `selected_intervention_type`. It always calls `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` fresh, finds the array element matching `SELECTED_INTERVENTION_TYPE`, and:
- Returns `REJECTED` if no such intervention type exists for the scope (verified: `NOT_A_REAL_TYPE` -> rejected, no row inserted).
- Returns `REJECTED` with the evaluator's own governed reason if `FEASIBLE <> TRUE` (verified: `EXPEDITE_CURRENT_SHIPMENT` for the flagship scope, currently infeasible because shipment SH900001 is already in transit -> rejected with that exact reason, no row inserted).
- Otherwise stores the **entire** matching array element verbatim as `RECOMMENDATION_SNAPSHOT` — quantity, cost, dates, rank, and the `RECOMMENDED` flag all come from this fresh call, never from the LLM.

## 8. State Machine

`PENDING -> APPROVED | REJECTED | CANCELLED`. All three are terminal — no transition out. A second decision on any terminal request is rejected with an explicit "already `<STATUS>`; requires a new approval request" message; **no event is appended and no status is mutated** on a rejected second-decision attempt.

**Concurrency hardening (discovered during testing):** an initial version of `REVIEW_INTERVENTION_APPROVAL_REQUEST` guarded the transition only with a pre-check (`SELECT` current status, then `IF <> 'PENDING'`); issuing two decisions **in true parallel** against the same request exposed a TOCTOU race where both calls read `PENDING` before either committed, allowing an already-`APPROVED` request to be silently `REJECTED`. **Fixed** by making the `UPDATE ... WHERE REQUEST_STATUS = 'PENDING'` itself the authoritative gate and checking `SQLROWCOUNT` immediately after: the event is inserted (and the transaction committed) only if exactly one row was actually updated; otherwise the transaction is rolled back and a "no longer PENDING" error is returned. Re-tested sequentially and confirmed correct; documented as a genuine concurrency-safety finding, not hidden.

## 9. Test Results (20+ tests, all PASS)

| # | Test | Result |
|---|---|---|
| 1 | Recommendation-only question | No row created (verified via before/after `COUNT(*)`) |
| 2 | Explicit "submit the recommended option" | Exactly one new `PENDING` row, full snapshot/hash/fingerprint stored |
| 3 | Explicit non-rank-1 feasible option (`ALTERNATE_SUPPLIER`, rank 3) | `PENDING`, rank preserved as 3, not rewritten to rank 1 |
| 4 | Infeasible option (`EXPEDITE_CURRENT_SHIPMENT`) | `REJECTED`, governed reason, no row |
| 5 | Invalid intervention type | `REJECTED`, no row |
| 6 | Natural-language flagship submission | resolver -> evaluate -> submit chain, `PENDING` created |
| 7 | Ambiguous entity ("Pinnacle") in a submission request | Stopped before `submit_intervention_for_approval`; candidates listed |
| 8 | Fuzzy entity (covered in Phase 8A chain; same gating logic reused for submission) | N/A trigger path shared with resolver gating — verified structurally via orchestration instructions |
| 9 | No-match entity | Same gating (shared resolver logic) |
| 10 | Exact duplicate resubmission while `PENDING` | Same `REQUEST_ID` returned, no duplicate row/event |
| 11 | Human approves a `PENDING` request | `APPROVED`, actor/role captured, one `APPROVED` event |
| 12 | Human rejects a different `PENDING` request | `REJECTED`, one `REJECTED` event |
| 13 | Human cancels a different `PENDING` request | `CANCELLED`, one `CANCELLED` event |
| 14 | Second decision on a terminal request (sequential) | Rejected with "already `<STATUS>`" error, no new event |
| 14b | Second decision issued in true parallel (race) | Initially exposed the race (fixed in §8); documented, not hidden |
| 15 | Agent cannot approve ("approve it yourself") | Agent explicitly refuses, explains human review is required, only looks up status |
| 16 | Approval preserves immutable snapshot/hash | Independently recomputed hash from stored snapshot == stored hash |
| 17 | Approval performs no operational execution | `OPERATIONAL_ACTION_EXECUTED = false` always returned; no write to any Phase 1–7 table at any point |
| 18 | Phase 7 operational-vs-contractual distinction preserved | Snapshot's `RISKS_OR_CONSTRAINTS`/`COST_BASIS` verbatim; Agent still states Road-vs-Air distinction and that DOC000217 does not authorize the Road option |
| 19 | Status lookup (`PENDING`, `APPROVED`, `NOT_FOUND`) | All three correct, `NOT_FOUND` governed for unknown IDs |
| 20 | Requester/approver identity capture | `REQUESTED_BY`/`REQUESTED_ROLE` and `APPROVED_OR_REJECTED_BY`/`APPROVER_ROLE` correctly populated (`ALEN`/`ACCOUNTADMIN` in this single-identity environment) |
| 21 | Idempotency conflict (Case B, changed evidence) | Isolated test-fixture hash/fingerprint override -> `CONFLICT`, no duplicate `PENDING`, stale request not silently reused |
| 22 | Case C (new request after terminal) | New distinct `REQUEST_ID` created for the same scope+type once the only prior request became terminal |
| 23 | Phase 8C structural handoff | Request row exposes `REQUEST_ID`, `REQUEST_STATUS`, `RECOMMENDATION_SNAPSHOT`, `RECOMMENDATION_HASH` sufficient for a future execution tool's contract (see §11) |

## 10. Flagship Test (end-to-end, real request)

1. *"What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries?"* -> resolver -> evaluator -> recommendation presented. **No approval row created** (confirmed via row count before/after).
2. *"Submit the recommended option for the ... shortage ... for approval."* -> resolver (all `EXACT_NAME`) -> evaluator (revalidated) -> `submit_intervention_for_approval('S017','P104','P01','EXPEDITED_REPLENISHMENT')` -> **`REQUEST_ID = AR-ce8b13d1-3cec-4571-92d8-4c2cd4001de2`**, `PENDING`, full snapshot/hash/fingerprint stored, `REQUESTED_BY = ALEN`/`REQUESTED_ROLE = ACCOUNTADMIN`. Agent response stated the exact `REQUEST_ID`, `PENDING` status, and "no operational action has been executed" — did not claim the expedite was placed.
3. Human approval, **outside the Agent**, via `REVIEW_INTERVENTION_APPROVAL_REQUEST('AR-ce8b13d1-...', 'APPROVE', 'Approved for demo validation - flagship natural-language submission')` -> `APPROVED`, actor `ALEN`/`ACCOUNTADMIN` recorded, one `APPROVED` event appended.
4. *"What is the status of approval request AR-ce8b13d1-...?"* asked to the Agent -> `get_intervention_approval_status` -> Agent correctly reported `APPROVED` and explicitly restated that approval does not mean execution has occurred.

## 11. Phase 8C Handoff Contract (documented, not implemented)

A future execution tool must, given only `REQUEST_ID`: require `REQUEST_STATUS = 'APPROVED'`; independently recompute `RECOMMENDATION_HASH` from the stored `RECOMMENDATION_SNAPSHOT` using the exact canonical order in §3 and confirm it matches the stored value; confirm the request has not already been marked executed (Phase 8C would add its own `EXECUTED_AT` tracking — not added here); freshly re-invoke `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` and compare the current feasibility/quantities against the approved snapshot; and refuse to execute (requiring renewed approval instead) if material facts have changed, while always preserving the original snapshot for audit regardless of outcome.

## 12. Separation of Duties / Single-Identity Limitation

This environment has exactly one real human identity (`ALEN`/`ACCOUNTADMIN`). The enforceable Phase 8B human/Agent boundary is **structural**: the Agent has no tool capable of invoking `REVIEW_INTERVENTION_APPROVAL_REQUEST` (verified: the Agent explicitly refused "just approve it yourself" and only used the read-only status tool). A `REQUESTED_BY != APPROVED_BY` check was **not** implemented, since it would make human review permanently untestable in this single-identity environment and is not a substitute for genuine separation of duties. **Production recommendation** (not implemented): a dedicated approver role, multiple real human identities, and only then a `REQUESTED_BY != APPROVED_BY` enforcement. This is not claimed as production-grade separation of duties.

## 13. No-Operational-Write Verification

Across all workflow tests (submission, feasibility rejection, approval, rejection, cancellation, conflict), zero writes occurred to any Phase 1–7 table. Verified two ways: (a) `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` re-invoked after the full test sequence returns byte-identical values to before (shortage 2150, same 4-option ranking, same dates/costs); (b) `GET_INTERVENTION_APPROVAL_STATUS` always returns `OPERATIONAL_ACTION_EXECUTED = false`.

## 14. Regression (Phase 6/7/8A, all unchanged)

Overall Supplier OTD 75.2% (`0.751929`), warranty no-hallucination response, structural counts (12 tables/15 relationships/26 facts/32 metrics/15 VQs, 14 CURATED views, Search 139/ACTIVE), and the Phase 7 operational-Road-vs-contractual-Air governance distinction all reproduced identically post-Phase-8B.

## 15. Privileges

`EXECUTE AS OWNER` on all three new procedures means Agent-execution roles need only `USAGE` on `SUPPLYCHAINIQ_DB`, `SUPPLYCHAINIQ_DB.WORKFLOW`, `COMPUTE_WH`, and `USAGE` on the three procedures themselves — **no direct `INSERT`/`UPDATE`/`SELECT`** on `INTERVENTION_APPROVAL_REQUEST`/`INTERVENTION_APPROVAL_EVENT` is required or should be granted to normal Agent-execution roles. The procedure owner (here `ACCOUNTADMIN`) needs `SELECT` on `CURATED.SUPPLIER`/`PART`/`PLANT`/etc. and `USAGE` on `EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` (already held).

## 16. Files

- `docs/approval_workflow_design.md` (this file)
- `sql/19_approval_workflow.sql` — schema, both tables, all three procedures, full 6-tool Agent redeploy
- `sql/20_approval_workflow_validation.sql` — structural validation, all direct-procedure tests, Agent end-to-end tests, regression

## 17. Hackathon Compliance

GA-only throughout: `UUID_STRING()`, `SHA2()`, `SYS_CONTEXT('SNOWFLAKE$SESSION',...)`, `CURRENT_TIMESTAMP()`, Snowflake Scripting explicit transactions (`BEGIN TRANSACTION`/`COMMIT`/`ROLLBACK`/`SQLROWCOUNT`), `EXECUTE AS OWNER` procedures, `generic`/`procedure` Cortex Agent custom tools. No Agent Skills, `code_execution` (Preview), MCP, external orchestration, or external system. No preview-feature dependency identified.

## 18. Warnings

- The identity-mechanism equivalence (`SYS_CONTEXT` vs. `CURRENT_USER()`) could not be tested under a genuinely different caller role in this single-identity environment.
- A real concurrency race was found and fixed in the review procedure (§8) — documented transparently rather than silently patched.
