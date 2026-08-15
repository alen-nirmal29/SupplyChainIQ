# SupplyChainIQ — Phase 1 Handoff

## Synthetic Enterprise Data Foundation

**Project:** SupplyChainIQ — Governed Agentic Supply Chain Control Tower  
**Phase:** 1 — Synthetic Enterprise Data Foundation  
**Status:** COMPLETE / VALIDATED  
**Dataset version:** 1  
**Dataset anchor date:** `2026-08-15`  
**Primary Snowflake database:** `SUPPLYCHAINIQ_DB`

---

## 1. Purpose of this handoff

This document is the working handoff for the next developer continuing SupplyChainIQ after Phase 1.

Phase 1 created and validated the Snowflake synthetic data foundation. The next developer should **not regenerate, rename, flatten, or reinterpret the raw source schemas casually**. The raw layer intentionally simulates fragmented enterprise systems so that later phases can demonstrate governed ontology, canonical business meaning, Semantic Views, Cortex Analyst, Cortex Search, Cortex Agents, scenario analysis, Streamlit, and controlled actions.

The intended progression is:

```text
Phase 1  Synthetic source data                  DONE
   ↓
Phase 2  Ontology + canonical CURATED model     NEXT
   ↓
Phase 3  Semantic View
   ↓
Phase 4  Cortex Analyst
   ↓
         Cortex Search
   ↓
         Cortex Agent
   ↓
         Agent skills / scenario analysis
   ↓
         Streamlit Control Tower
   ↓
         Human approval + MCP action layer
```

---

## 2. Phase 1 completion summary

Phase 1 completed successfully with:

- `SUPPLYCHAINIQ_DB` created.
- 8 project schemas created.
- `CURATED` intentionally left empty.
- ~390K synthetic business records generated.
- Cross-system naming fragmentation intentionally preserved.
- 23/23 referential checks returning zero orphans.
- No malformed/null canonical business IDs.
- Inventory and demand coverage aligned for DOI and stockout-risk readiness.
- Deterministic flagship scenario validated.
- Three intervention options validated.
- Eight future governed metrics confirmed source-ready.
- Supplier documents generated for future Cortex Search.
- SQL generation and validation scripts retained for reproducibility.

**Reported total major synthetic records:** `389,999`

---

## 3. Snowflake environment

| Item | Value |
|---|---|
| Role used | `ACCOUNTADMIN` |
| Warehouse | `COMPUTE_WH` |
| Warehouse size | X-Small |
| New warehouse created? | No |
| Database | `SUPPLYCHAINIQ_DB` |
| Dataset version | `1` |
| Dataset anchor date | `2026-08-15` |
| Snowflake session date during build | `2026-08-14` |
| Session timezone during build | `America/Los_Angeles` |
| Snowflake version reported | `10.28.101` |

### Important anchor-date rule

`2026-08-15` is a **fixed project anchor date** for dataset version 1.

Historical records and future demo events are derived from this anchor. Do not replace the project anchor with a live `CURRENT_DATE()` in later logic unless a new dataset version is intentionally designed.

The anchor is stored in:

```text
SUPPLYCHAINIQ_DB.PUBLIC.DATASET_METADATA
```

---

## 4. Schema architecture

The database intentionally represents multiple fragmented enterprise systems.

```text
SUPPLYCHAINIQ_DB
│
├── SAP_ERP
├── TMS_LOGISTICS
├── WMS_INVENTORY
├── DEMAND_PLANNING
├── CRM_ORDERS
├── SUPPLIER_PORTAL
├── DOCUMENTS
├── CURATED
├── PUBLIC
└── INFORMATION_SCHEMA
```

### Project schemas

#### `SAP_ERP`
Synthetic ERP/procurement/master-data source.

#### `TMS_LOGISTICS`
Synthetic transportation and logistics source.

#### `WMS_INVENTORY`
Synthetic warehouse/inventory source.

#### `DEMAND_PLANNING`
Synthetic planning/forecasting source.

#### `CRM_ORDERS`
Synthetic customer/order source.

#### `SUPPLIER_PORTAL`
Synthetic supplier scorecard/profile source.

#### `DOCUMENTS`
Synthetic contracts, SLAs, policies, quality agreements, and scorecard narratives.

#### `CURATED`
**Intentionally empty at Phase 1 completion.**

This is where Phase 2 should create the canonical ontology-aligned model.

### `PUBLIC`
Contains dataset metadata and generation-support infrastructure.

---

## 5. Actual table inventory

> Note: the early execution plan described 15 tables, but the completion report shows **16 business/source tables**, plus PUBLIC support tables. Use the actual database state as authoritative.

### `SAP_ERP`

| Table | Purpose | Actual rows |
|---|---|---:|
| `VENDOR_MASTER` | Supplier master | 100 |
| `MATERIAL_MASTER` | Part/material master | 1,000 |
| `PLANT_MASTER` | Plant master | 12 |
| `SUPPLIER_MATERIAL` | Supplier ↔ Part sourcing map | 1,401 |
| `PURCHASE_ORDER_LINES` | Purchase order lines | 54,871 |

### `TMS_LOGISTICS`

| Table | Purpose | Actual rows |
|---|---|---:|
| `CARRIER_MASTER` | Carrier master | 20 |
| `SHIPMENTS` | Shipment-line facts | 54,024 |
| `TRANSPORT_OPTIONS` | Normal/expedite transport choices | 96 |
| `INTERPLANT_TRANSFER_OPTIONS` | Plant-to-plant transfer choices | 42 |

### `WMS_INVENTORY`

| Table | Purpose | Actual rows |
|---|---|---:|
| `INVENTORY_SNAPSHOTS` | Historical inventory snapshots | 104,000 |

### `DEMAND_PLANNING`

| Table | Purpose | Actual rows |
|---|---|---:|
| `DEMAND_HISTORY` | Historical forecast/actual demand | 120,000 |

### `CRM_ORDERS`

| Table | Purpose | Actual rows |
|---|---|---:|
| `CUSTOMER_MASTER` | Synthetic business customers | 500 |
| `CUSTOMER_ORDER_LINES` | Customer-order lines | 52,494 |

### `SUPPLIER_PORTAL`

| Table | Purpose | Actual rows |
|---|---|---:|
| `SUPPLIER_SCORECARDS` | Supplier scorecard history | 1,200 |
| `SUPPLIER_PROFILE` | Supplier profile / name-format drift | 100 |

### `DOCUMENTS`

| Table | Purpose | Actual rows |
|---|---|---:|
| `SUPPLIER_DOCUMENTS` | Contracts, SLAs, policies, narratives | 139 |

### `PUBLIC`

Known support tables include:

- `DATASET_METADATA`
- `PART_SITE_COVERAGE`

`PART_SITE_COVERAGE` is generation infrastructure, not a business ontology entity.

---

## 6. Key grains and volumes

Reported dataset grains:

- `22,001` distinct purchase orders
- `54,871` purchase-order lines
- `25,150` distinct shipments
- `54,024` shipment lines
- `21,003` distinct customer orders
- `52,494` customer-order lines
- `2,000` active Part × Plant combinations
- `52` weekly inventory snapshots per active combination
- `60` daily demand records per active combination

Reported duplicate checks:

- Zero duplicates across all six business-key grains.

---

## 7. Intentional cross-system fragmentation

This is a core project design requirement.

Do **not** normalize raw source column names in-place.

### Supplier identifier

| Source | Field |
|---|---|
| SAP ERP | `VENDOR_ID` |
| TMS | `SUPPLIER_CODE` |
| Supplier Portal | `SUPPLIER_ID` |

### Part identifier

| Source | Field |
|---|---|
| SAP ERP | `MATERIAL_NO` |
| TMS | `ITEM_CODE` |
| WMS | `SKU` |
| Planning | `PART_ID` |
| CRM | `PART_NUMBER` |

### Plant identifier

| Source | Field |
|---|---|
| SAP ERP | `PLANT_CODE` |
| TMS | `DESTINATION_SITE` |
| WMS | `SITE_ID` |
| Planning | `LOCATION_ID` |
| CRM | `FULFILLMENT_SITE` |

### Date terminology also differs

Examples:

- `PROMISED_DATE`
- `EXPECTED_DELIVERY_DATE`
- `PROJECTED_DELIVERY_DATE`
- `REQUESTED_DATE`
- `DUE_DATE`
- `SNAPSHOT_DATE`
- `DEMAND_DATE`

This inconsistency is intentional and exists so Phase 2 can build a canonical governed model.

---

## 8. Canonical business IDs

Stable IDs are intentionally preserved across source systems.

Examples:

- Suppliers: `S001` … `S100`
- Parts: `P001` … `P1000`
- Plants: `P01` … `P12`
- Customers: `C0001` onward
- Carriers: `CR01` onward
- Purchase orders: `PO...`
- Shipments: `SH...`
- Customer orders: `CO...`

Do not corrupt or remap these IDs without a documented reason.

---

## 9. Referential integrity status

Phase 1 validation reported:

- **23 of 23 referential checks = 0 orphans**
- Total canonical business-key orphans = `0`
- Inventory Part × Site combinations lacking demand history = `0`
- Canonical-ID NULL/malformed checks = `0`
- Invalid date/quantity relationships = `0`

Snowflake does not enforce PK/FK constraints here; integrity is guaranteed by generation logic and validation queries.

---

## 10. Important distribution validation

### Shipment distribution

Reported over 54,024 shipment lines:

- On time: `57.2%`
- Late: `16.3%`
- Early: `12.9%`
- Not delivered: `13.6%`
  - In transit: `11.9%`
  - Planned: `1.7%`
- Partial shipment: `12.0%`

Also:

- `3,947` PO lines are fulfilled by more than one shipment.

### Purchase-order status

- Delivered: `71.6%`
- Partially delivered: `11.6%`
- Overdue: `9.6%`
- Cancelled: `3.9%`
- Open: `3.3%`

### Customer orders

- Fulfilled: `65.4%`
- Partially fulfilled: `12.9%`
- Overdue: `11.2%`
- Open: `6.6%`
- Cancelled: `4.0%`
- Partially fulfilled lines: `23.6%`

### Supplier risk — latest scorecard

- Medium: `62`
- Low: `28`
- High: `8`
- Critical: `2`

### Part criticality

- Medium: `399`
- Low: `300`
- High: `200`
- Critical: `101`

### Latest inventory status

- Healthy: `32.3%`
- Excess: `30.6%`
- Below safety: `14.6%`
- Stockout: `11.7%`
- At safety: `11.0%`

---

## 11. Flagship demo scenario — DO NOT BREAK

This is the main deterministic scenario for the hackathon demo.

### Core relationship

```text
Supplier S017
      ↓
Part P104
      ↓
Plant P01
```

### Supplier

`S017`

Reported attributes:

- Supplier name: Pinnacle Industries
- Region: APAC
- Country: China
- Tier: Standard
- Status: Active

### Part

`P104`

- Critical part

### Plant

`P01`

Primary impacted plant in the flagship scenario.

---

## 12. Flagship inventory calculation

Latest snapshot:

| Fact | Value |
|---|---:|
| On hand | 8,200 |
| Reserved | 0 |
| Available | 8,200 |
| Safety stock | 3,000 |

Safe usable inventory:

```text
8,200 - 3,000 = 5,200 units
```

---

## 13. Flagship demand

For P104 at P01:

- Latest 30 historical days total actual demand = `21,000`
- Average daily demand = `700.00 units/day`

This value is derived from demand history, not stored as a final answer.

---

## 14. Flagship delayed inbound shipment

### Purchase order

`PO900001`

Reported details:

- Supplier: S017
- Part: P104
- Plant: P01
- Quantity: 6,000
- Unit price: CNY 395
- Status: OPEN
- Promised date: `2026-08-25`

### Shipment

`SH900001`

- Status: in transit
- Expected delivery: `2026-08-25`
- Projected delivery: `2026-08-30`
- Actual delivery: NULL
- Delay: exactly `5 days`

The delayed inbound arrives after all three critical customer-order due dates.

---

## 15. Flagship customer impact

There are exactly three critical/open P104/P01 order lines in the critical window.

| Order requirement | Quantity |
|---|---:|
| A | 2,500 |
| B | 2,400 |
| C | 2,450 |
| **Total** | **7,350** |

All three have:

- `FULFILLED_QTY = 0`
- Open status
- Critical/High priority
- Strategic/Enterprise customers
- Due dates: `2026-08-27`, `2026-08-28`, `2026-08-29`

Combined revenue exposure:

```text
INR 4,200,000
```

---

## 16. Flagship shortage

Do not hard-code this as an answer in later application code.

It must remain derivable:

```text
Customer requirement              7,350
Safe usable inventory            -5,200
                                 ------
Projected shortage                2,150 units
```

Expected flagship output:

- Affected customer orders: `3`
- Projected shortage: `2,150`
- Revenue exposure: `INR 4,200,000`
- Shipment delay: `5 days`

---

## 17. Intervention option 1 — Expedite S017 shipment

Validated:

- Active APAC → P01 lanes exist.
- Air option:
  - normal transit: 9 days
  - expedited transit: 4 days
  - normal cost factor: 1.000
  - expedite cost factor: 2.600
- Expedited arrival: `2026-08-19`
- First customer due date: `2026-08-27`

Result:

**Time-feasible.**

Later scenario logic should compute incremental cost and risk; it should not automatically recommend this option.

---

## 18. Intervention option 2 — P03 → P01 transfer

P104 at P03:

| Fact | Value |
|---|---:|
| Available | 6,500 |
| Safety stock | 2,500 |
| Safely transferable | 4,000 |

Required transfer to close flagship shortage:

```text
2,150 units
```

Transfer lane:

- Origin: P03
- Destination: P01
- Mode: Road
- Transit: 3 days
- Max quantity: 5,000
- Cost: INR 45/unit
- Fixed cost: INR 25,000
- Reported cost to transfer 2,150 units: INR 121,750
- Arrival: `2026-08-18`

Result:

**Feasible, and P03 remains above its own safety stock.**

---

## 19. Intervention option 3 — Alternate supplier S042

S042 is an approved alternate for P104.

Reported values:

- Active supplier
- Non-primary supplier for P104
- Contract lead time: `7 days`
- Arrival from anchor: `2026-08-22`
- Max weekly supply: `4,500`
- Risk: Low
- Service score: `93`
- Quality score: `97`
- Rejection rate: `0.40%`
- Lead-time variability: `1.0`
- Historical OTD: `88.7%`

S017 comparison:

- Historical OTD: `49.4%`
- Lead-time variability: `7.32`

### Currency warning

The completion report lists:

- S017 P104 purchase price: `CNY 395`
- S042 P104 purchase price: `INR 431`

These values **must not be compared directly** as if they were in the same currency.

Phase 2 / later scenario modeling must introduce a governed FX normalization approach before making cross-currency cost comparisons.

---

## 20. Documents available for future Cortex Search

`DOCUMENTS.SUPPLIER_DOCUMENTS` contains synthetic text documents, including:

- Supplier Contracts
- SLAs
- Procurement Policies
- Supplier Scorecard Narratives
- Logistics Policies
- Quality Agreements

Documents exist for both S017 and S042.

Reported examples:

- S017 SLA: ~3,037 chars
- S017 Contract: ~2,983 chars

These should later be indexed using Cortex Search so the agent can retrieve supplier obligations, lead-time commitments, delivery requirements, penalties, escalation terms, etc.

---

## 21. Eight future governed metrics — source readiness

Phase 1 confirmed all required source fields are present for:

1. On-Time Delivery (OTD)
2. Fill Rate
3. Days of Inventory (DOI)
4. Landed Cost
5. Lead Time
6. Inventory Turnover
7. Supplier Risk Score
8. Stockout Risk

### Important rule

Do **not** calculate competing definitions independently in random SQL views, Python code, or Streamlit.

The canonical definitions should be documented in `metric_catalog.md` and then encoded into the Semantic View.

---

## 22. Canonical metric intent

### On-Time Delivery — OTD

Intended governed meaning:

```text
eligible delivery lines delivered on or before promised date
-------------------------------------------------------------
eligible delivery lines
```

Important:

- Early delivery counts as successful OTD.
- Exactly-on-promised-date counts as successful OTD.
- Late delivery fails OTD.
- Cancelled PO lines should be excluded from the eligible population.

The raw validation reports Early and On-Time separately for operational analysis; the canonical OTD definition should combine both successful categories appropriately.

### Fill Rate

```text
fulfilled quantity / ordered quantity
```

Subject to governed cancellation/partial-order rules.

### Days of Inventory

```text
available inventory / governed average daily demand
```

### Landed Cost

```text
purchase cost
+ freight
+ duties
+ handling
+ governed additional logistics costs
```

### Lead Time

Actual delivery date minus governed order/confirmation date.

### Inventory Turnover

Annualized consumption divided by average inventory.

### Supplier Risk Score

Governed composite using appropriate factors such as:

- OTD
- lead-time variability
- quality
- rejection rate
- service performance
- open-order exposure

### Stockout Risk

Governed risk based on:

- current inventory
- demand
- inbound supply
- safety stock
- lead time / shipment delay

---

## 23. Controlled data-quality issues

Intentional fragmentation includes:

- Different terminology across systems.
- Minor supplier display-name formatting differences.
- Optional NULL values.
- Partial shipments.
- Partial fulfillment.
- Cancelled records.
- Early deliveries.
- Late deliveries.
- Multiple shipments against a PO line.
- Source-specific date fields.

Reported intentional NULL examples:

- `CONFIRMATION_DATE`: 1.97%
- `OTHER_LOGISTICS_COST`: 5.15%
- Open shipment `ACTUAL_DELIVERY_DATE`: 13.64%
- Company-wide policies with NULL `SUPPLIER_ID`: 5 rows

80 of 100 suppliers reportedly have display-name formatting drift between ERP and portal while retaining a stable 1:1 canonical ID.

---

## 24. Secondary test scenarios

The completion report states all 15 deliberate scenarios are query-visible.

Named examples:

- `S011` — high-performing supplier
- `S088` — repeated late delivery
- `S073` — poor quality with otherwise good delivery
- `S055` — deteriorating supplier
- `S042` — costly/reliable alternate supplier

Additional dataset conditions:

- 611 excess inventory positions
- 233 stockout positions
- 12,382 partially fulfilled lines
- 2,135 cancelled PO lines
- 3,947 multi-shipment PO lines
- 6,952 early shipments
- 6,426 in-transit shipments
- 246 volatile-demand combinations
- P07 intentionally represents high inventory / weak demand

These scenarios should be preserved for later semantic-model testing and evaluation.

---

## 25. Known limitation — currency / FX

This is the most important known modeling gap.

Source purchase/logistics costs can be expressed in the supplier's default currency while CRM order value is treated as INR.

Before building cross-supplier cost recommendations or canonical landed-cost comparisons, Phase 2 or a subsequent phase should introduce a governed FX layer.

Suggested future structure:

```text
CURATED.FX_RATE
--------------
FROM_CURRENCY
TO_CURRENCY
EFFECTIVE_DATE
FX_RATE
```

Possible canonical outputs:

```text
UNIT_PRICE_INR
PURCHASE_COST_INR
FREIGHT_COST_INR
DUTY_COST_INR
HANDLING_COST_INR
OTHER_LOGISTICS_COST_INR
LANDED_COST_INR
```

Do not overwrite the original source-currency values.

---

## 26. Other limitations / assumptions

- CRM `ORDER_VALUE` is treated as INR according to Phase 1 notes.
- `CUSTOMER_ORDER_LINES` does not currently contain a currency column.
- Snowflake PK/FK constraints are not declared/enforced; integrity is validation-driven.
- Latest excess-inventory share is intentionally higher than a typical real network because scenario coverage was deliberately introduced.
- The 30-day average-demand window is currently a validation convention, not yet a canonical metric definition.
- The 14-day risk horizon is currently a flagship-demo/business-question convention, not a universal canonical rule.
- If `GENERATED_AT` is execution-time-based, describe the dataset as **deterministic/reproducible**, not necessarily literal byte-for-byte identical across runs.

---

## 27. SQL artifacts

Phase 1 produced:

```text
sql/
├── 01_database.sql
├── 02_tables.sql
├── 03_seed_data.sql
└── 04_data_validation.sql
```

### `01_database.sql`

Contains:

- database creation
- 8 schema creation
- dataset metadata
- fixed anchor date
- shared Part × Site coverage infrastructure

### `02_tables.sql`

Contains:

- source-system table DDL
- source-specific naming conventions

### `03_seed_data.sql`

Contains:

- set-based deterministic data generation
- `GENERATOR`
- hash-based deterministic pseudo-randomness
- normal business distributions
- flagship overrides
- secondary scenarios

### `04_data_validation.sql`

Contains validation for:

- row counts
- grains/duplicates
- referential integrity
- distributions
- flagship scenario
- interventions
- metric readiness
- fragmentation/data-quality checks
- final pass/fail gate

---

## 28. Corrections already made during Phase 1

Do not reintroduce these issues.

### 1. Ambiguous `VENDOR_ID` in document generator

Cause:

- A document-generator branch selected `s.VENDOR_ID` and `s.*`, duplicating the column.

Fix:

- Duplicate-column projection removed.
- Documents regenerated successfully.
- Final document count: 139.

### 2. Shipment lateness too high / supplier reliability not differentiated

Initial issue:

- Late deliveries ~30%.
- S017 and S042 OTD too similar.

Fix:

- Shipment timing aligned more coherently with promised dates.
- Supplier reliability made differentiated.

Final reported result:

- Late shipments: 16.3%
- S017 OTD: 49.4%
- S042 OTD: 88.7%

### 3. Demand-pattern skew

Initial issue:

- Linear modulo logic collapsed some pattern classes.

Fix:

- Hash-based pattern assignment.

Final result:

- All 8 demand patterns represented.
- Approximately 230–266 combinations each.

### 4. Reserved-word validation alias

`ROWS` alias was renamed.

### 5. Supplier deterioration trend check

Materiality threshold added so noise does not incorrectly classify supplier deterioration.

---

## 29. Do-not-change rules

Before Phase 2, preserve these rules.

### Do not alter raw semantics casually

Do not rename raw source columns merely to make them consistent.

### Do not break canonical IDs

Preserve supplier, part, plant, order, shipment, and customer IDs.

### Do not break the flagship scenario

Protect:

```text
S017 → P104 → P01
```

and its validated quantities/timing.

### Do not populate CURATED with arbitrary transformations

Phase 2 should first define the ontology and canonical mapping design.

### Do not hard-code calculated answers

Do not store:

```text
PROJECTED_SHORTAGE = 2150
```

simply because the demo expects it.

It must remain derivable.

### Do not define canonical metrics multiple times

The metric catalog and Semantic View should become the source of truth.

### Do not compare source prices across currencies directly

Add FX normalization first.

### Do not build Cortex Agent / Streamlit before the semantic foundation

The intended project differentiator is governed meaning, not a generic chatbot.

---

## 30. Phase 2 objective

The next developer should start with:

# Ontology + Canonical CURATED Model

Phase 2 should define the shared business meaning before Semantic View implementation.

Expected canonical entities:

- Supplier
- Part
- Plant
- Purchase Order
- Shipment
- Inventory
- Customer Order
- Customer
- Demand
- Carrier

Potential supporting canonical concepts:

- Supplier-Part sourcing relationship
- Supplier performance/scorecard
- Transport option
- Interplant transfer option
- Document metadata
- FX rates

---

## 31. Phase 2 documentation to create

Recommended:

```text
docs/
├── ontology.md
├── metric_catalog.md
├── personas.md
└── phase1_handoff.md
```

### `ontology.md`

Should define:

- entities
- keys
- attributes
- relationships
- cardinalities
- hierarchies
- source mappings
- canonical grain

### `metric_catalog.md`

Should define for every canonical metric:

- name
- business definition
- exact formula
- grain
- owner
- included records
- excluded records
- date semantics
- synonyms
- source tables
- required fields
- edge-case behavior

### `personas.md`

At minimum:

- Procurement
- Planning
- Logistics
- Executive

The semantic layer must later prove that different personas asking equivalent questions resolve to the same canonical metric.

---

## 32. Recommended Phase 2 canonical mapping direction

Example only; finalize in the ontology before implementation.

```text
RAW SOURCES
──────────────────────────────────────

SAP_ERP.VENDOR_MASTER.VENDOR_ID
TMS_LOGISTICS.SHIPMENTS.SUPPLIER_CODE
SUPPLIER_PORTAL.SUPPLIER_ID

                  ↓

CURATED.SUPPLIER.SUPPLIER_ID
```

```text
SAP_ERP.MATERIAL_MASTER.MATERIAL_NO
TMS_LOGISTICS.SHIPMENTS.ITEM_CODE
WMS_INVENTORY.INVENTORY_SNAPSHOTS.SKU
DEMAND_PLANNING.DEMAND_HISTORY.PART_ID
CRM_ORDERS.CUSTOMER_ORDER_LINES.PART_NUMBER

                  ↓

CURATED.PART.PART_ID
```

```text
SAP_ERP.PLANT_MASTER.PLANT_CODE
TMS_LOGISTICS.SHIPMENTS.DESTINATION_SITE
WMS_INVENTORY.INVENTORY_SNAPSHOTS.SITE_ID
DEMAND_PLANNING.DEMAND_HISTORY.LOCATION_ID
CRM_ORDERS.CUSTOMER_ORDER_LINES.FULFILLMENT_SITE

                  ↓

CURATED.PLANT.PLANT_ID
```

---

## 33. Hierarchies required later

### Supplier hierarchy

```text
Global → Region → Country → Supplier
```

### Product hierarchy

```text
Product Family → Product Category → Part
```

### Geography hierarchy

```text
Global → Region → Country → Plant
```

### Time hierarchy

```text
Year → Quarter → Month → Week → Day
```

---

## 34. Semantic-layer proof expected later

The final system should prove that the same metric resolves identically across personas.

Example OTD questions:

### Procurement

> What is supplier OTD for Q3?

### Logistics

> How are suppliers performing on delivery this quarter?

### Planning

> What percentage of inbound deliveries were on time?

These should resolve to the same governed OTD definition where semantically applicable.

---

## 35. Future Cortex Search direction

`DOCUMENTS.SUPPLIER_DOCUMENTS` should later become the basis for a Cortex Search service.

Likely searchable content includes:

- contracts
- SLAs
- logistics policies
- procurement policies
- quality agreements
- supplier scorecard narratives

The agent should use:

- governed structured analytics for metrics and facts
- Cortex Search for contractual/policy evidence

---

## 36. Future agent direction

The future SupplyChainIQ agent should be able to:

1. Detect a supply-chain risk.
2. Identify root cause.
3. Trace Supplier → Part → Plant → Inventory → Customer Order impact.
4. Quantify customer/revenue exposure.
5. Retrieve supporting supplier/contract evidence.
6. Compare intervention options.
7. Recommend an option using governed facts/costs/constraints.
8. Require explicit human approval before external action.
9. Produce an auditable result.

---

## 37. Handoff checklist for the next developer

Before changing anything:

- [ ] Confirm access to `SUPPLYCHAINIQ_DB`.
- [ ] Confirm `COMPUTE_WH` or another approved warehouse.
- [ ] Read this handoff fully.
- [ ] Inspect `PUBLIC.DATASET_METADATA`.
- [ ] Inspect the 8 project schemas.
- [ ] Verify `CURATED` is still empty.
- [ ] Review `sql/01_database.sql`.
- [ ] Review `sql/02_tables.sql`.
- [ ] Review `sql/03_seed_data.sql`.
- [ ] Review `sql/04_data_validation.sql`.
- [ ] Spot-check S017 / P104 / P01.
- [ ] Confirm the three intervention datasets still exist.
- [ ] Do not rename raw columns.
- [ ] Do not redefine canonical metrics yet.
- [ ] Start Phase 2 with ontology design.
- [ ] Define canonical grains and cardinalities.
- [ ] Define FX-normalization strategy.
- [ ] Create `ontology.md`.
- [ ] Create `metric_catalog.md`.
- [ ] Create `personas.md`.
- [ ] Only then populate `CURATED`.
- [ ] Re-run Phase 1 validation if any raw-layer modification becomes necessary.

---

## 38. Phase 1 acceptance status

| Area | Status |
|---|---|
| Database foundation | PASS |
| Source schemas | PASS |
| Data volume | PASS |
| Referential integrity | PASS |
| Duplicate/grain checks | PASS |
| Fragmentation realism | PASS |
| Inventory-demand alignment | PASS |
| Flagship scenario | PASS |
| Expedite option | PASS |
| Interplant transfer option | PASS |
| Alternate supplier option | PASS |
| Supplier document readiness | PASS |
| Eight-metric source readiness | PASS |
| CURATED left empty | PASS |
| Semantic layer not prematurely created | PASS |

---

# Final handoff state

**Phase 1 is complete.**

The authoritative working database is:

```text
SUPPLYCHAINIQ_DB
```

The synthetic raw source layer is validated and ready for ontology design.

The next task is:

```text
PHASE 2
Ontology + Canonical CURATED Model
```

Do not skip directly to Cortex Analyst, Cortex Agent, or Streamlit.

The project should continue from governed business meaning first.
