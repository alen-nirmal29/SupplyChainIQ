# SupplyChainIQ — Governed Metric Catalog (Phase 3)

This is the single governed source of truth for SupplyChainIQ's canonical business metrics.
It reflects the approved Phase 3A design and the Phase 3A revision corrections, and documents
the exact implementation status of each metric in `SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW`.

| # | Metric | Status |
|---|---|---|
| 1 | Supplier On-Time Delivery (OTD) | **IMPLEMENT IN SEMANTIC VIEW** |
| 2 | Fill Rate | **IMPLEMENT IN SEMANTIC VIEW** |
| 3 | Days of Inventory (DOI) | **GOVERNED COMPONENT METRICS ONLY** — final division deferred to a two-step Analyst/Agent calculation |
| 4 | Actual Landed Cost | **IMPLEMENT IN SEMANTIC VIEW** |
| 5 | Lead Time | **IMPLEMENT AS THREE DISTINCT METRICS** — Contract / Realized / Reported Lead Time |
| 6 | Inventory Turnover | **DEFERRED** — no costed-inventory/COGS source exists |
| 7 | Supplier Risk | **USE EXISTING `RISK_CATEGORY`** — no new score |
| 8 | Stockout Risk | **EXPOSE SOURCE-GOVERNED `INVENTORY_STATUS`** — projected/forward-looking version deferred to a future Agent Skill |

---

## 1. Supplier On-Time Delivery (OTD)

- **Definition:** Percentage of eligible inbound shipment lines that arrived on or before the supplier's original PO commitment date.
- **Formula:** `SUM(on-time eligible count) / NULLIF(SUM(eligible count), 0)`, where on-time is `ACTUAL_DELIVERY_DATE <= PROMISED_DATE`.
- **Grain:** shipment line (`CURATED.SHIPMENT`), joined N→1 to its parent `CURATED.PURCHASE_ORDER_LINE` for `PROMISED_DATE`.
- **Source fields:** `SHIPMENT.ACTUAL_DELIVERY_DATE`, `SHIPMENT.SHIPMENT_STATUS`, `PURCHASE_ORDER_LINE.PROMISED_DATE`, `PURCHASE_ORDER_LINE.PO_STATUS`.
- **Eligible rows:** `SHIPMENT_STATUS IN ('DELIVERED','PARTIAL')` AND `ACTUAL_DELIVERY_DATE IS NOT NULL` AND parent `PO_STATUS != 'CANCELLED'`.
- **Excluded rows:** `IN_TRANSIT`, `PLANNED` shipments (no actual delivery date yet); shipments tied to a `CANCELLED` PO line.
- **Date semantics:** period attribution by `ACTUAL_DELIVERY_DATE` (when the delivery event occurred).
- **NULL handling:** rows with NULL `ACTUAL_DELIVERY_DATE` are excluded from eligibility entirely.
- **Denominator handling:** return NULL when the eligible-row count is 0 (`NULLIF(..., 0)`), not 0% or an error.
- **Aggregation rules:** ratio of aggregated counts (`SUM(on-time)/SUM(eligible)`) — never an average of pre-aggregated row-level percentages.
- **Synonyms:** on-time delivery, supplier delivery performance, vendor delivery performance, on-time percentage. (Deliberately excludes "shipment schedule adherence" and "logistics on-time rate" — reserved for the distinct concept below.)
- **Currency:** not applicable.
- **Implementation location:** `SUPPLY_CHAIN_SEMANTIC_VIEW`, `SHIPMENT` logical table, public metric `SUPPLIER_OTD_PERCENT`, backed by private helper metrics `ELIGIBLE_DELIVERY_COUNT` and `ON_TIME_DELIVERY_COUNT`.
- **Business owner:** `[Procurement / Logistics Ops — TBD]`.

### Related but distinct: Shipment Schedule Adherence
- **Definition:** Percentage of eligible shipment lines that met their own (possibly re-planned) logistics target, i.e., `ACTUAL_DELIVERY_DATE <= EXPECTED_DELIVERY_DATE`.
- **This is NOT canonical Supplier OTD.** Same eligibility/exclusion/date-attribution rules as OTD, differing only in the comparison field (`EXPECTED_DELIVERY_DATE` on `SHIPMENT`, not `PROMISED_DATE` on the parent PO line).
- **Synonyms:** shipment schedule adherence, logistics on-time rate, shipment target adherence. (Deliberately excludes OTD's synonyms to prevent ambiguity.)
- **Implementation location:** `SUPPLY_CHAIN_SEMANTIC_VIEW`, `SHIPMENT` logical table, public metric `SHIPMENT_SCHEDULE_ADHERENCE_PERCENT`.

## 2. Fill Rate

- **Definition:** Percentage of ordered quantity that was fulfilled, at the customer-order-line grain.
- **Formula:** `SUM(FULFILLED_QTY) / NULLIF(SUM(ORDERED_QTY), 0)`.
- **Grain:** customer order line (`CURATED.CUSTOMER_ORDER_LINE`).
- **Source fields:** `ORDERED_QTY`, `FULFILLED_QTY`, `ORDER_STATUS`, `ORDER_DATE`, `DUE_DATE`.
- **Eligible rows:** all order lines except `ORDER_STATUS = 'CANCELLED'`.
- **Excluded rows:** `CANCELLED` order lines.
- **Date semantics:** default period attribution = `ORDER_DATE` for generic period questions (e.g., "Fill Rate for Q3"); use `DUE_DATE` only when the question explicitly refers to orders due/committed during a period.
- **NULL handling:** none expected — both quantity fields are populated across all observed statuses.
- **Denominator handling:** return NULL when `SUM(ORDERED_QTY) = 0` in a filtered slice.
- **Aggregation rules:** `SUM(FULFILLED_QTY)/SUM(ORDERED_QTY)` — never `AVG(row-level FULFILLED_QTY/ORDERED_QTY)`, which would misweight small vs. large orders.
- **Synonyms:** fulfillment rate, order fulfillment, quantity fulfillment.
- **Currency:** not applicable (quantity-based).
- **Implementation location:** `SUPPLY_CHAIN_SEMANTIC_VIEW`, `CUSTOMER_ORDER_LINE` logical table, public metric `FILL_RATE_PERCENT`.
- **Business owner:** `[Customer Ops / Supply Planning — TBD]`.

## 3. Days of Inventory (DOI) — Governed Component Metrics Only

- **Canonical business definition:** latest `AVAILABLE_QTY` ÷ trailing 30-calendar-day average `ACTUAL_DEMAND_QTY`, for a given Part × Plant.
- **Why not one native metric:** DOI requires combining two independent facts (`Inventory Snapshot`, `Demand`) that share only `(PART_ID, PLANT_ID)` at different, incompatible grains (weekly snapshot vs. daily demand). `Demand` is not unique on `(PART_ID, PLANT_ID)` alone, so no valid `RELATIONSHIPS ... REFERENCES` path can be declared between them without violating the uniqueness requirement Snowflake enforces — declaring one would either fail validation or silently create a fan-out. This is a genuine, empirically-grounded native limitation, not a stylistic choice.
- **Component A — Latest Inventory:**
  - `INVENTORY_SNAPSHOT.LATEST_SNAPSHOT_DATE` — public metric, `MAX(SNAPSHOT_DATE)`. Safe, ordinary additive `MAX` aggregate.
  - `INVENTORY_SNAPSHOT.AVAILABLE_QTY`, `.ON_HAND_QTY`, `.SAFETY_STOCK_QTY` — public metrics, queryable together with the `SNAPSHOT_DATE` dimension.
  - **Empirically tested and rejected approach:** a single "auto-latest" metric using `NON ADDITIVE BY (snapshot_date DESC)` on `MAX(AVAILABLE_QTY)` was tested and does **not** correctly resolve to the value at the latest snapshot date when `SNAPSHOT_DATE` is excluded from the query (returned 8,488 instead of the correct 8,200 for Part P104 / Plant P01) — `NON ADDITIVE BY` only guards against invalid cross-date aggregation; it does not implement "latest value" selection. This was empirically confirmed and the approach was discarded.
  - **Correct, validated pattern (two-step):** (1) query `LATEST_SNAPSHOT_DATE` for the Part/Plant; (2) filter `AVAILABLE_QTY`/`SAFETY_STOCK_QTY`/`ON_HAND_QTY` `WHERE SNAPSHOT_DATE = <that date>`. Empirically validated for Part P104 / Plant P01: `LATEST_SNAPSHOT_DATE = 2026-08-15`, `AVAILABLE_QTY = 8200`, `SAFETY_STOCK_QTY = 3000` — both match the Phase 2 validated flagship baseline exactly.
- **Component B — Trailing 30-Day Average Demand:**
  - `DEMAND.AVG_DAILY_DEMAND_30D` — public window-function metric: `AVG(daily_actual_demand) OVER (PARTITION BY EXCLUDING demand_date ORDER BY demand_date RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW)`, built on a private helper `DEMAND.DAILY_ACTUAL_DEMAND = SUM(ACTUAL_DEMAND_QTY)`.
  - `DEMAND_DATE` is a **required** dimension for this metric (Snowflake enforces this for window-function metrics whose frame orders by an excluded dimension) — the caller must specify the date to evaluate the trailing window as of.
  - **Empirically validated:** queried at `DEMAND_DATE = 2026-08-14` (the latest actual demand date available — one day before the dataset anchor, since demand data ends at anchor−1) for Part P104 / Plant P01, returned exactly `700.00000`, matching the Phase 1/Phase 2 governed 30-day-window baseline.
- **Final DOI calculation:** `LATEST(AVAILABLE_QTY) / AVG_DAILY_DEMAND_30D`, computed as a governed **two-step Cortex Analyst / future Cortex Agent calculation** — query Component A, query Component B (at the correct corresponding date), divide at the application layer. This is not implemented as a single native Semantic View metric.
- **Zero-demand behavior:** if `AVG_DAILY_DEMAND_30D = 0`, the two-step consumer must treat DOI as undefined/infinite, not display 0 or error.
- **Safety stock relationship:** DOI uses `AVAILABLE_QTY`, not `AVAILABLE_QTY - SAFETY_STOCK_QTY` — the latter is a distinct "safe usable inventory" concept used elsewhere (e.g., the flagship shortage calculation), not part of the DOI formula itself.
- **Implementation location:** `SUPPLY_CHAIN_SEMANTIC_VIEW` — component metrics on `INVENTORY_SNAPSHOT` and `DEMAND` logical tables; final division deferred to query/application layer.
- **Business owner:** `[Inventory Planning — TBD]`.

## 4. Actual Landed Cost

- **Definition:** total realized cost to land inbound goods at the plant for a given shipment line.
- **Formula:** `(RECEIVED_QTY × parent PO UNIT_PRICE) + COALESCE(FREIGHT_COST,0) + COALESCE(DUTY_COST,0) + COALESCE(HANDLING_COST,0) + COALESCE(OTHER_LOGISTICS_COST,0)`.
- **Grain:** shipment line (`CURATED.SHIPMENT`), joined N→1 to its parent `CURATED.PURCHASE_ORDER_LINE` for `UNIT_PRICE` and `CURRENCY`.
- **Source fields:** `SHIPMENT.RECEIVED_QTY`, `SHIPMENT.FREIGHT_COST`, `SHIPMENT.DUTY_COST`, `SHIPMENT.HANDLING_COST`, `SHIPMENT.OTHER_LOGISTICS_COST`, `PURCHASE_ORDER_LINE.UNIT_PRICE`, `PURCHASE_ORDER_LINE.CURRENCY`.
- **Eligible rows:** shipment lines with `SHIPMENT_STATUS IN ('DELIVERED','PARTIAL')` — cost is only realized/known for received goods.
- **Excluded rows:** `IN_TRANSIT`, `PLANNED` shipments (not yet received; no realized cost).
- **CRITICAL — fan-out correction:** the formula uses each shipment line's own `RECEIVED_QTY`, **not** the parent PO line's `ORDER_QTY`. Using `ORDER_QTY` at shipment grain would duplicate the full PO purchase amount once per shipment line whenever a PO line has multiple shipments (3,947 of 50,077 PO lines with shipments have exactly 2 shipment lines). Empirically validated: `SUM(RECEIVED_QTY)` per PO line never exceeds `ORDER_QTY` for either single-shipment (46,130 lines) or split-shipment (3,947 lines) PO lines — zero over-received rows in either group — confirming this formula cannot duplicate purchase cost.
- **Date semantics:** attribute by `SHIP_DATE` or `ACTUAL_DELIVERY_DATE` depending on the question (recommend `ACTUAL_DELIVERY_DATE` as default, consistent with OTD's period attribution, since cost is only realized on delivery).
- **NULL handling:** `COALESCE(...,0)` applied to all four logistics cost components — a NULL component contributes zero, not a NULL total.
- **Denominator handling:** not applicable (not a ratio metric).
- **Currency behavior:** `CURRENCY` is inherited from the parent PO line and exposed as an accessible dimension (`PURCHASE_ORDER_LINE.CURRENCY`). **11 distinct currencies exist in this dataset with no FX source.** Aggregation is allowed only within a single currency (single supplier, single part restricted to one supplier, or explicitly grouped by `CURRENCY`). `NON ADDITIVE BY (CURRENCY)` is deliberately **not** used for this purpose — `NON ADDITIVE BY` is a semi-additive/latest-value guard, not a currency-grouping enforcement mechanism (confirmed via the DOI-latest-inventory empirical test above, where it failed to enforce correct "latest" semantics). Currency safety here is enforced instead via `AI_SQL_GENERATION` instructions plus documented governance (see below) and validated via explicit SQL tests (`sql/07_semantic_view_validation.sql` §D) proving no mixed-currency total is ever presented as a single number.
- **Aggregation rules:** additive within one currency; must `GROUP BY CURRENCY` when aggregating beyond a single supplier/part.
- **Synonyms:** landed cost, all-in delivered cost, total inbound landed cost.
- **Implementation location:** `SUPPLY_CHAIN_SEMANTIC_VIEW`, `SHIPMENT` logical table, public metric `ACTUAL_LANDED_COST`.
- **Business owner:** `[Procurement Finance — TBD]`.

## 5. Lead Time (Three Distinct Metrics — No Ambiguous Single "Lead Time")

| Metric | Formula | Grain | Source |
|---|---|---|---|
| `CONTRACT_LEAD_TIME_DAYS` | passthrough | Supplier-Part | `SUPPLIER_PART.CONTRACT_LEAD_TIME_DAYS` — the agreed contractual commitment |
| `REALIZED_LEAD_TIME_DAYS` | `DATEDIFF(day, PO.ORDER_DATE, SHIPMENT.ACTUAL_DELIVERY_DATE)` | Shipment (joined to parent PO Line), `DELIVERED`/`PARTIAL` only | `PURCHASE_ORDER_LINE.ORDER_DATE`, `SHIPMENT.ACTUAL_DELIVERY_DATE` — what actually happened |
| `REPORTED_LEAD_TIME_DAYS` | passthrough | Supplier Performance (monthly) | `SUPPLIER_PERFORMANCE.REPORTED_LEAD_TIME_DAYS` — the portal-reported figure |

- These three concepts are genuinely different data sources measuring different things (a contractual promise, an actual outcome, and a self-reported monthly figure) and must never be collapsed into one "Lead Time" metric/synonym bucket — doing so would recreate the exact persona ambiguity the OTD governance work was designed to prevent.
- **Implementation location:** `CONTRACT_LEAD_TIME_DAYS` on `SUPPLIER_PART`; `REALIZED_LEAD_TIME_DAYS` on `SHIPMENT`; `REPORTED_LEAD_TIME_DAYS` on `SUPPLIER_PERFORMANCE`.
- **Business owner:** `[Procurement — TBD]`.

## 6. Inventory Turnover — DEFERRED

- **Status:** not implemented. No costed-inventory or COGS field exists in the Phase 1/Phase 2 data (`INVENTORY_SNAPSHOT` is quantity-only by design). No quantity-based proxy is exposed under this name, per explicit governance direction — implementing an approximate metric under the canonical "Inventory Turnover" name would misrepresent it as the real financial metric.
- **Future path:** requires a costed-inventory or COGS source before implementation.

## 7. Supplier Risk

- **Definition:** the existing source-governed multidimensional risk classification from the supplier scorecard process.
- **Source field:** `SUPPLIER_PERFORMANCE.RISK_CATEGORY` (values: Low, Medium, High, Critical), plus its supporting measures `QUALITY_SCORE`, `REJECTION_RATE`, `REPORTED_LEAD_TIME_DAYS`, `LEAD_TIME_VARIABILITY`, `SERVICE_SCORE`, `OPEN_ISSUE_COUNT`.
- **Grain:** Supplier × Scorecard Month.
- **No new score is invented.** `RISK_CATEGORY` and its component measures are exposed as-is, at their native monthly grain.
- **"Current" risk:** obtainable by filtering to the latest `SCORECARD_DATE` per supplier — a safe, simple filter, not a new scoring formula.
- **Implementation location:** `SUPPLIER_PERFORMANCE` logical table — dimension `RISK_CATEGORY`, facts/metrics for the component scores.
- **Business owner:** `[Supplier Risk Management — TBD]`.

## 8. Stockout Risk

- **Definition (implemented):** the existing source-governed inventory status classification.
- **Source field:** `INVENTORY_SNAPSHOT.INVENTORY_STATUS` (values: HEALTHY, AT_SAFETY, BELOW_SAFETY, STOCKOUT, EXCESS).
- **Grain:** Part × Plant × Snapshot Date.
- **Implementation location:** `INVENTORY_SNAPSHOT` logical table — dimension `INVENTORY_STATUS`.
- **Deferred:** projected/forward-looking Stockout Risk (e.g., "will this part stock out in the next N days given current demand") requires combining `Inventory Snapshot` and `Demand` — the same unsafe cross-fact computation identified for DOI. This remains deferred to a future Agent Skill, not implemented as a native Semantic View metric.
- **Business owner:** `[Inventory Planning — TBD]`.
