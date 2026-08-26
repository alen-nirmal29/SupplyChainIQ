# SupplyChainIQ Proactive Risk Intelligence Design

## 1. Purpose

Risk Radar evaluates current governed supply-chain data when its page is
loaded or refreshed. It identifies current shortage exposure, ranks risks,
explains the supported supplier-to-customer impact chain, and surfaces the
existing deterministic intervention recommendation for important risks.

It is not continuous background monitoring. It does not create approvals,
approve, reject, dispatch, or update operational source data.

## 2. Risk grain and identifier

The risk grain is `Supplier x Part x Destination Plant`. The supplier is the
single deterministic active source for the part: a current primary supplier
is preferred; otherwise the lowest canonical `SUPPLIER_ID` is selected. This
is the same grain accepted by
`DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS`.

`RISK_ID = RISK::<supplier_id>::<part_id>::<plant_id>`.

`RISK.SUPPLY_CHAIN_RISK_CANDIDATES` emits one row at this grain. The source
supplier selection and the view's one-row-per-grain design prevent duplicate
logical risks.

## 3. Governed input signals

All inputs are read from existing governed views:

- Latest `CURATED.INVENTORY_SNAPSHOT`: available quantity and safety stock.
- `CURATED.CUSTOMER_ORDER_LINE`: open, non-cancelled/non-fulfilled demand due
  from the dataset reference date through the following 14 days; remaining
  quantity, first due date, affected line count, and INR order exposure.
- `CURATED.SHIPMENT` and `CURATED.PURCHASE_ORDER_LINE`: a current in-transit
  shipment delayed against its promised date.
- Historical eligible delivery rows in those same views: supplier OTD.
- `CURATED.SUPPLIER_PART` and `CURATED.SUPPLIER`: deterministic source
  attribution with current active agreements.

The 14-day demand horizon and shortage formula are deliberately aligned to
the existing intervention evaluator. Usable inventory is governed as
`GREATEST(available quantity - safety stock, 0)`. A candidate exists only
when governed open requirement exceeds usable inventory.

Supplier attribution uses the governed sourcing agreement effective window:
`VALID_FROM <= DATASET_ANCHOR_DATE` and `VALID_TO >= DATASET_ANCHOR_DATE`.
The base table comment defines `SUPPLIER_MATERIAL` as the approved sourcing
relationship for which vendor may supply which material, at what price, lead
time, and capacity. The seeded governed data creates current agreements with
`VALID_FROM` before, and `VALID_TO` after, the dataset anchor date; this
supports treating both dates as the effective sourcing window for current
primary-source attribution.

The existing intervention evaluator is slightly broader in one internal
lookup: its direct supplier-capacity CTE reads the requested
`SUPPLIER_ID`/`PART_ID` agreement without repeating the `VALID_FROM`
predicate, while alternate-supplier candidates require `VALID_TO` at the
reference date. Risk Radar keeps the stricter current-agreement rule because
it is choosing the single active source supplier automatically. The evaluator
is still the authority once a concrete supplier/part/plant scope has been
selected, and current seeded data does not show this stricter source
attribution excluding the supported S017/P104 relationship.

## 4. Deterministic score and severity

`RISK.SUPPLY_CHAIN_RISK_RANKING` is the sole risk-score implementation. The
total is a bounded 100-point score:

| Component | Formula | Maximum |
| --- | --- | ---: |
| Shortage | `45 * shortage / requirement` | 45 |
| Urgency | Due within 3 / 7 / 14 days = 20 / 15 / 8 | 20 |
| Revenue | `15 * risk revenue exposure / maximum current candidate exposure` | 15 |
| Shipment | `min(delay days, 10)` when an in-transit shipment is delayed | 10 |
| Supplier | `10 * (1 - historical supplier OTD)` when OTD is available | 10 |

The revenue component is normalized against the live candidate population,
not an invented currency threshold. Every component is shown in the Risk
Radar and is bounded by the validation SQL.

Severity thresholds are exact: `CRITICAL >= 70`, `HIGH >= 50`,
`MEDIUM >= 30`, and `LOW < 30`. Ranking is `RISK_SCORE DESC, RISK_ID ASC`,
so equal scores have deterministic order.

## 5. Recommendation integration and performance

Risk Radar never selects an intervention in Python or through an LLM. For
Critical and High displayed risks only, it calls the existing read-only
`DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS(supplier, part, plant)` through
the owner read connection's Snowpark session. It selects the returned record
where the evaluator has set `RECOMMENDED = true`.

Automatic calls are bounded to the top 10 qualifying displayed risks per
page load/refresh. Lower-severity or out-of-bound records can be evaluated
only after the manager explicitly opens their comparison. This avoids an
unbounded procedure call for every potential supplier/part/plant combination.

The evaluator remains the only source for feasibility, recommendation rank,
quantity used, shortage after, arrival, cost basis, and constraints.

## 6. Root-cause / impact chain

The detail view presents a reusable, UI-friendly chain composed from backend
values only:

1. Supplier: attributed supplier and governed historical OTD when available.
2. Shipment: a delayed in-transit shipment and delay days when one is
   attributable; otherwise that absence is stated.
3. Inventory constraint: available, safety stock, requirement, and governed
   shortage at the Part x Plant.
4. Customer impact: affected open customer-order lines, first due date, and
   INR customer-order exposure.
5. Recommended response: only the evaluator's recommended option and its
   returned reason.

This deliberately stops at supplier/shipment -> inventory -> customer
delivery exposure. The repository has no governed BOM, production order, or
work-order chain.

## 7. What-if / intervention comparison

The Risk Radar's **What-if / intervention simulator** is read-only and
clearly labelled **SIMULATION ONLY**. It displays every option returned by
the existing evaluator: feasibility, quantity, transit/lead days, expected
arrival, shortage after, cost, currency, cost basis, constraints, rank, and
recommended flag.

It does not compare values as equivalent when the evaluator marks costs as
not comparable or provides different cost bases. It invokes no approval,
review, execution, or dispatch procedure.

## 8. UI flow

Navigation is `Overview -> Risk Radar -> Ask SupplyChainIQ -> Approvals ->
Actions -> Timeline`. Overview uses `TOP ACTIVE RISK` only when the RISK view
is available; otherwise it retains the clearly captioned preselected demo
scenario and does not claim automatic discovery.

Risk Radar provides live summary metrics, optional severity/supplier/plant/
part filters, a ranked table, a selected detail view, evidence, comparison,
governance explanation, and a suggested Cortex Agent investigation prompt.

## 9. Governance controls

- Governed Snowflake data supplies all business calculations.
- The deterministic RISK view, not an LLM or Python, scores and ranks risks.
- The existing deterministic evaluator, not an LLM or Python, chooses the
  recommended intervention.
- Procedure calls are read-only evaluation calls; no approval row or action
  row is created by Risk Radar.
- DEV validation should prove evaluator side-effect safety by capturing
  `WORKFLOW.INTERVENTION_APPROVAL_REQUEST` and
  `ACTION.INTERVENTION_ACTION_COMMAND` row counts before and after a manual
  `DECISION.EVALUATE_SUPPLY_CHAIN_INTERVENTIONS` call for a known risk. The
  expected result is identical before/after counts for both tables.
- Existing restricted-caller review semantics, approval snapshot/hash,
  fresh-state validation, and action state machines are unchanged.
- `DISPATCHED_DEMO` remains a Snowflake action-command record, not an external
  SAP, TMS, WMS, or physical operational change.

## 10. Limitations and future enhancements

- Evaluation is page-load/refresh driven, not continuous monitoring.
- Supplier attribution is the deterministic current source agreement for the
  part; it is not a claim of a complete causal supplier allocation model.
- Only top 10 Critical/High displayed risks receive automatic recommendation
  enrichment per render.
- Contractual/SLA authorization remains a Cortex Search/Agent investigation;
  operational recommendation does not establish contractual approval.
- No BOM, production order, work order, forecasting ML, external feeds,
  notifications, scheduled tasks, or autonomous action is included.

## 11. Local implementation and required DEV work

The repository changes are local only. To activate this feature in DEV, a
reviewer must execute `sql/24_risk_intelligence.sql`, grant the Streamlit
runtime role `USAGE` on schema `RISK` and `SELECT` on both RISK views, execute
`sql/25_risk_intelligence_validation.sql`, and then deploy the Streamlit
artifact to the DEV application. No production deployment is implied.

Before live execution, perform a static source-mutation check on
`sql/24_risk_intelligence.sql`: it should contain only additive RISK schema
and view DDL, with no `INSERT`, `UPDATE`, `DELETE`, `MERGE`, or `TRUNCATE`
against existing business tables. The validation script documents this as a
required static check rather than copying large governed datasets.
