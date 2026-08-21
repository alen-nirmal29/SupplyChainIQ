# SupplyChainIQ — Cortex Analyst Verified Query Catalog (Phase 4B)

Governed source of truth for the 15 Verified Queries (VQ01–VQ11, VQ12_V2,
VQ13–VQ15) registered in
`SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW` via `AI_VERIFIED_QUERIES`.

**Catalog counts:**
- **Total registered VQs = 15** (VQ01–VQ11, VQ12_V2, VQ13–VQ15). The original
  `VQ12` was retired and replaced by `VQ12_V2` — see the VQ12_V2 entry below
  for the ground-truth fix and the `vq12_refresh_check` partial-evaluation
  artifact that necessitated the identity change.
- **Formal evaluation candidates (Phase 4C) = 14** — all registered VQs except VQ03
- **Runtime-guidance-only VQ = VQ03** — `FORMAL_EVALUATION = FALSE`

All other VQs: `FORMAL_EVALUATION = TRUE`.

---

## VQ01 — `VQ_SUPPLIER_OTD_OVERALL`
- **Question:** "What is our overall supplier OTD?"
- **SQL:**
```sql
SELECT SUPPLIER_OTD_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS shipment.supplier_otd_percent
)
```
- **Expected result:** `0.751929` (≈75.19%)
- **Onboarding:** TRUE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Anchors canonical Supplier OTD (PO `PROMISED_DATE`, never `EXPECTED_DELIVERY_DATE`) with zero filters.

## VQ02 — `VQ_SUPPLIER_OTD_BY_ID`
- **Question:** "What is the on-time delivery rate for supplier S017?"
- **SQL:**
```sql
SELECT SUPPLIER_ID, SUPPLIER_OTD_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id
  METRICS shipment.supplier_otd_percent
)
WHERE SUPPLIER_ID = 'S017'
```
- **Expected result:** `0.493506` (≈49.35%)
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Confirms filtered OTD generalizes correctly; the flagship risk supplier.

## VQ03 — `VQ_SUPPLIER_OTD_BUSINESS_PHRASING`
- **Question:** "How is supplier S017 performing on inbound delivery commitments?"
- **SQL:** identical to VQ02.
- **Expected result:** `0.493506` (identical to VQ02 by design)
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** **FALSE**
- **Governance purpose:** Teaches phrasing-invariance (persona consistency) at runtime. Excluded from formal evaluation because it is numerically identical to VQ02 and would add no discriminative evaluation value.

## VQ04 — `VQ_SHIPMENT_SCHEDULE_ADHERENCE_OVERALL`
- **Question:** "What is our shipment schedule adherence?"
- **SQL:**
```sql
SELECT SHIPMENT_SCHEDULE_ADHERENCE_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS shipment.shipment_schedule_adherence_percent
)
```
- **Expected result:** `0.811793` (≈81.18%)
- **Onboarding:** TRUE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Anchors the distinct (non-OTD) logistics KPI; its numeric contrast with OTD is itself the teaching signal.

## VQ05 — `VQ_FILL_RATE_OVERALL`
- **Question:** "What is our overall fill rate?"
- **SQL:**
```sql
SELECT FILL_RATE_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS cust_order_line.fill_rate_percent
)
```
- **Expected result:** `0.77578916` — **the one authoritative live baseline; no competing 77.55%/77.58% figure is valid.**
- **Onboarding:** TRUE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Anchors `SUM(FULFILLED_QTY)/SUM(ORDERED_QTY)` (cancelled excluded) as the sole Fill Rate formula.

## VQ06 — `VQ_CURRENT_INVENTORY_P104_P01`
- **Question (evaluation-stable):** "What was the available inventory for part P104 at plant P01 on 2026-08-15?"
- **SQL:**
```sql
SELECT PART_ID, PLANT_ID, SNAPSHOT_DATE, AVAILABLE_QTY_METRIC
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date
  METRICS inv.available_qty_metric
)
WHERE PART_ID = 'P104' AND PLANT_ID = 'P01' AND SNAPSHOT_DATE = '2026-08-15'
```
- **Expected result:** `AVAILABLE_QTY_METRIC = 8200`
- **Onboarding:** TRUE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Single-statement, deterministic pin to the validated anchor snapshot. The general "resolve latest date, then filter" two-step pattern for undated "current inventory" questions remains governed via `AI_SQL_GENERATION`, not via this VQ's SQL.

## VQ07 — `VQ_AVG_DAILY_DEMAND_30D_P104_P01`
- **Question:** "What is the 30-day average daily demand for part P104 at plant P01 as of 2026-08-14?"
- **SQL:**
```sql
SELECT PART_ID, PLANT_ID, DEMAND_DATE, AVG_DAILY_DEMAND_30D
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, demand.demand_date
  METRICS demand.avg_daily_demand_30d
)
WHERE PART_ID = 'P104' AND PLANT_ID = 'P01' AND DEMAND_DATE = '2026-08-14'
```
- **Expected result:** `AVG_DAILY_DEMAND_30D = 700.00000`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Teaches the mandatory `demand_date` dimension requirement for this window-function metric, and which date to use (latest actual-demand date, one day before the dataset anchor).

## VQ08 — `VQ_CONTRACT_LEAD_TIME_S017_S042_P104` (corrective — Improvement Area A)
- **Question:** "What are the contract lead times for suppliers S017 and S042 for P104?"
- **SQL:**
```sql
SELECT SUPPLIER_ID, PART_ID, CONTRACT_LEAD_TIME_DAYS_AVG
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, part.part_id
  METRICS supplier_part.contract_lead_time_days_avg
)
WHERE PART_ID = 'P104' AND SUPPLIER_ID IN ('S017', 'S042')
ORDER BY SUPPLIER_ID
```
- **Expected result:** `S017 = 28`, `S042 = 7`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** **Primary corrective mechanism for Phase 4A over-clarification Behavior A.** Uses the exact previously-over-clarified phrasing to teach direct resolution to `contract_lead_time_days_avg` without a clarifying question.

## VQ09 — `VQ_CURRENT_SUPPLIER_RISK_S017`
- **Question:** "What is the current risk category for supplier S017?"
- **SQL:**
```sql
SELECT SUPPLIER_ID, SCORECARD_DATE, RISK_CATEGORY
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, supplier_perf.scorecard_date, supplier_perf.risk_category
)
WHERE SUPPLIER_ID = 'S017'
ORDER BY SCORECARD_DATE DESC
LIMIT 1
```
- **Expected result:** `SCORECARD_DATE = 2026-07-31`, `RISK_CATEGORY = Critical`
- **Onboarding:** TRUE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Demonstrates the "latest record via ORDER BY DESC LIMIT 1" pattern; reinforces `RISK_CATEGORY` as the canonical, non-invented risk signal.

## VQ10 — `VQ_CUSTOMER_ORDER_EXPOSURE_P104_P01` (flagship)
- **Question (evaluation-stable):** "How many non-cancelled customer order lines for P104 at P01 are due between 2026-08-15 and 2026-08-29, and what is their total order value?"
- **SQL:**
```sql
SELECT PART_ID, PLANT_ID, ORDER_LINE_COUNT, TOTAL_ORDER_VALUE
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id
  METRICS COUNT(cust_order_line.order_id) AS ORDER_LINE_COUNT, cust_order_line.total_order_value
  WHERE cust_order_line.order_status <> 'CANCELLED' AND cust_order_line.due_date BETWEEN '2026-08-15' AND '2026-08-29'
)
WHERE PART_ID = 'P104' AND PLANT_ID = 'P01'
```
- **Expected result:** `ORDER_LINE_COUNT = 3`, `TOTAL_ORDER_VALUE = 4200000`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Empirically-validated pattern: status/date filters go in `SEMANTIC_VIEW(...)`'s **inner** `WHERE` (pre-aggregation) so `COUNT(cust_order_line.order_id)` collapses to one row instead of fragmenting by date. Direct hit on the flagship S017/P104/P01 scenario.

## VQ11 — `VQ_LANDED_COST_BY_CURRENCY` (corrective — Improvement Area B)
- **Question:** "What is the total actual landed cost across all suppliers, broken down by currency?"
- **SQL:**
```sql
SELECT CURRENCY, ACTUAL_LANDED_COST
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS po_line.currency
  METRICS shipment.actual_landed_cost
)
ORDER BY CURRENCY
```
- **Expected result:** 11 currency rows (BRL, CNY, EUR, INR, JPY, KRW, MXN, PLN, TRY, USD, VND), never one collapsed grand total.
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** **Primary corrective mechanism for Phase 4A over-clarification Behavior B.** Uses the exact previously-over-clarified phrasing to teach direct generation of the currency-grouped result.

## VQ12_V2 — `VQ_LANDED_COST_SINGLE_SUPPLIER` (replaces retired VQ12)
- **Question:** "What are the actual landed cost and currency for supplier S017?"
- **SQL:**
```sql
SELECT CURRENCY, ACTUAL_LANDED_COST
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, po_line.currency
  METRICS shipment.actual_landed_cost
)
WHERE SUPPLIER_ID = 'S017'
```
- **Expected result:** `CURRENCY = CNY`, `ACTUAL_LANDED_COST = 3624295146.29`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Paired with VQ11 — teaches that single-supplier scope needs no currency grouping (only one governed currency), but `CURRENCY` is still surfaced explicitly rather than left implicit. SUPPLIER_ID is intentionally omitted from the output projection because the supplier identifier is already supplied as a filter in the natural-language question; projecting it would be redundant. The `supplier.supplier_id` dimension remains in the DIMENSIONS clause solely to enable the WHERE filter.
- **Phase 4C note (v4 failure classification):** The phase4c_baseline_v4 VQ12 failure was an evaluation ground-truth / result-shape mismatch, not a semantic calculation failure. Cortex Analyst correctly filtered to S017 and returned the correct CURRENCY=CNY and ACTUAL_LANDED_COST=3624295146.29, but received 0.0 because the ground-truth SQL projected SUPPLIER_ID which the model's generated SQL reasonably omitted (the user already specified S017 in the question). The deployed VQ12 SQL was corrected (SUPPLIER_ID removed from SELECT) immediately after this finding.
- **Phase 4C note (vq12_refresh_check partial-evaluation artifact):** A subsequent single-VQ evaluation run named "vq12_refresh_check" (selecting only the corrected VQ12) failed BEFORE evaluation with a temporary-YAML parse error at VQ01 ("expected <block end>, but found '<scalar>' at: SELECT SUPPLIER_OTD_PERCENT"). Root cause: when an evaluation run selects only a SUBSET of registered Verified Queries, Snowflake removes the SELECTED VQ(s) from the temporary in-memory evaluation-model YAML but leaves the UNSELECTED VQs in place, producing a malformed AI_VERIFIED_QUERIES block that fails to parse at the next entry. This is an evaluation-tooling / partial-selection artifact, NOT a Cortex Analyst accuracy failure and NOT a VQ12 semantic defect — the run never reached query execution/scoring, so it could not confirm or refute the VQ12 SQL fix. Resolution: the corrected VQ12 was retired and re-registered under a fresh Verified Query identity, `VQ12_V2` (new QUESTION, new VERIFIED_AT, identical corrected SQL), so that the next evaluation run selects ALL 15 Verified Queries (VQ01-VQ11, VQ12_V2, VQ13-VQ15) together, avoiding the partial-selection YAML parsing problem.

## VQ13 — `VQ_APPROVED_SUPPLIERS_P104_PRICE_LEAD_TIME`
- **Question:** "Which suppliers are approved to supply P104, and what are their contract lead times and prices?"
- **SQL:**
```sql
SELECT SUPPLIER_ID, PART_ID, CURRENCY, AGREED_UNIT_PRICE, CONTRACT_LEAD_TIME_DAYS_AVG
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, part.part_id, supplier_part.currency
  METRICS MAX(supplier_part.agreed_unit_price) AS AGREED_UNIT_PRICE, supplier_part.contract_lead_time_days_avg
)
WHERE PART_ID = 'P104'
ORDER BY SUPPLIER_ID
```
- **Expected result:** `S017 / P104 / CNY / 395.00 / 28.000000`, `S042 / P104 / INR / 431.00 / 7.000000`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Empirically validated pattern — `MAX(supplier_part.agreed_unit_price)` as an **inline ad-hoc aggregation directly inside `METRICS`**, requiring no new public price metric. Supports alternate-sourcing questions combining price and lead time.

## VQ14 — `VQ_INVENTORY_AT_RISK_LATEST`
- **Question (evaluation-stable):** "Which parts and plants had inventory status BELOW_SAFETY or STOCKOUT on 2026-08-15?"
- **SQL:**
```sql
SELECT PART_ID, PLANT_ID, SNAPSHOT_DATE, INVENTORY_STATUS
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date, inv.inventory_status
)
WHERE SNAPSHOT_DATE = '2026-08-15' AND INVENTORY_STATUS IN ('BELOW_SAFETY', 'STOCKOUT')
ORDER BY INVENTORY_STATUS, PART_ID, PLANT_ID
```
- **Expected result:** a deterministic row set of Part×Plant combinations at `INVENTORY_STATUS IN ('BELOW_SAFETY','STOCKOUT')` on the anchor date.
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Demonstrates the categorical (point-in-time, source-governed) Stockout Risk signal. Explicitly not the deferred projected/forward-looking calculation.

## VQ15 — `VQ_OVERDUE_PO_LINES_BY_SUPPLIER`
- **Question:** "Which suppliers have the most overdue purchase order lines?"
- **SQL:**
```sql
SELECT SUPPLIER_ID, OVERDUE_LINE_COUNT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id
  METRICS COUNT(po_line.po_number) AS OVERDUE_LINE_COUNT
  WHERE po_line.po_status = 'OVERDUE'
)
ORDER BY OVERDUE_LINE_COUNT DESC
LIMIT 10
```
- **Expected result (top 3):** `S077 = 137`, `S017 = 132`, `S097 = 126`
- **Onboarding:** FALSE | **Runtime guidance:** TRUE | **Formal evaluation:** TRUE
- **Governance purpose:** Empirically validated status-based procurement triage pattern using `COUNT(po_line.po_number)` with an inner `WHERE po_line.po_status = 'OVERDUE'`.

---

## Explicit Exclusions (No VQ Exists For)
- **Inventory Turnover** — unsupported (no costed-inventory/COGS source); no proxy VQ created.
- **Projected/forward-looking Stockout Risk** — deferred to a future Agent Skill; no VQ created.
- **Transport Option / Interplant Transfer Option scenario analysis** (expedite, interplant transfer optimization) — out of Cortex Analyst Phase 4 scope; no VQ created.

## Empirically Validated Query Mechanics Used Throughout
1. **Inline ad-hoc `METRICS` aggregation** — `MAX(supplier_part.agreed_unit_price)`, `COUNT(cust_order_line.order_id)`, `COUNT(po_line.po_number)` are all valid directly inside `METRICS` without any pre-declared public metric.
2. **`SEMANTIC_VIEW(...)`'s own inner `WHERE` clause** filters *before* aggregation without adding the filtered column to the output grain — required whenever a filter column (e.g., `order_status`, `due_date`, `po_status`) should not fragment the result grouping.
3. Bare `COUNT(*)` is **not** valid inside `METRICS`; a row-level column reference (e.g., `COUNT(table.id_column)`) must be used instead.
