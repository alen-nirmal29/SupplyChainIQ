# SupplyChainIQ

## Governed Agentic Supply Chain Control Tower

SupplyChainIQ is a Snowflake-native supply-chain intelligence platform being developed for the Snowflake CoCo CLI Hackathon.

The project addresses a common enterprise problem: supply-chain information is distributed across ERP, logistics, warehouse, planning, supplier and customer systems that use different schemas, terminology and business definitions.

SupplyChainIQ creates a governed semantic foundation so Planning, Procurement, Logistics and Executive users can ask supply-chain questions and receive consistent answers based on shared business definitions.

The long-term solution combines:

- Snowflake data foundation
- Supply-chain ontology
- Canonical curated model
- Snowflake Semantic Views
- Cortex Analyst
- Cortex Search
- Cortex Agents
- Agent skills
- Scenario analysis
- Streamlit Control Tower
- Human-approved MCP actions
- Evaluation and auditability

---

# Project Goal

SupplyChainIQ is designed to move beyond a generic supply-chain chatbot.

The target workflow is:

```text
Fragmented enterprise data
        ↓
Canonical business model
        ↓
Governed Semantic View
        ↓
Natural-language analytics
        ↓
Agentic risk investigation
        ↓
Scenario comparison
        ↓
Recommended intervention
        ↓
Human approval
        ↓
Controlled action
```

A representative end-to-end question is:

> What supply-chain risk threatens customer deliveries, why is it happening, what can we do about it, and what action should we take?

---

# Current Status

## Phase 1 — Synthetic Enterprise Data Foundation

**Status: COMPLETE AND VALIDATED**

Phase 1 created a realistic synthetic supply-chain environment in Snowflake.

Database:

```text
SUPPLYCHAINIQ_DB
```

The current source schemas are:

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
└── PUBLIC
```

`CURATED` is intentionally empty at the end of Phase 1.

It will be populated during Phase 2 after the ontology and canonical data model are formally defined.

---

# Synthetic Data Foundation

Phase 1 generated approximately **390,000 synthetic business records**.

Major datasets include:

| Dataset | Records |
|---|---:|
| Suppliers | 100 |
| Parts | 1,000 |
| Plants | 12 |
| Supplier-Part mappings | 1,401 |
| Purchase-order lines | 54,871 |
| Carriers | 20 |
| Shipment lines | 54,024 |
| Inventory snapshots | 104,000 |
| Demand history | 120,000 |
| Customers | 500 |
| Customer-order lines | 52,494 |
| Supplier scorecards | 1,200 |
| Supplier profiles | 100 |
| Supplier documents | 139 |

The dataset uses a fixed project anchor date:

```text
2026-08-15
```

This keeps the synthetic business scenarios reproducible.

---

# Enterprise Fragmentation

The source schemas deliberately use different names for the same business concepts.

For example:

## Supplier

```text
SAP ERP          VENDOR_ID
TMS              SUPPLIER_CODE
Supplier Portal  SUPPLIER_ID
```

## Part

```text
SAP ERP          MATERIAL_NO
TMS              ITEM_CODE
WMS              SKU
Planning         PART_ID
CRM              PART_NUMBER
```

## Plant

```text
SAP ERP          PLANT_CODE
TMS              DESTINATION_SITE
WMS              SITE_ID
Planning         LOCATION_ID
CRM              FULFILLMENT_SITE
```

These differences are intentional.

Phase 2 will harmonize them into a canonical business model rather than modifying the raw source systems.

---

# Flagship Demo Scenario

The primary deterministic scenario is:

```text
Supplier S017
      ↓
Part P104
      ↓
Plant P01
```

Current validated facts:

```text
Available inventory        8,200
Safety stock               3,000
Safe usable inventory      5,200

Critical customer demand   7,350

Projected shortage         2,150 units

Affected customer orders   3
Revenue exposure           INR 4,200,000
Supplier shipment delay    5 days
Average daily demand       700 units/day
```

The shortage is derived from the underlying records:

```text
7,350 customer requirement
-
5,200 safe usable inventory
=
2,150 unit shortage
```

The final application must calculate this from governed data rather than hard-code the answer.

---

# Intervention Options

The synthetic data also supports three intervention scenarios.

## 1. Expedite Supplier Shipment

An expedited transportation option is available that reduces transit time at higher logistics cost.

## 2. Interplant Transfer

Plant P03 has sufficient excess P104 inventory to transfer at least 2,150 units to P01 without violating its own safety-stock requirement.

## 3. Alternate Supplier

Supplier S042 is an approved alternate supplier for P104 with:

- better historical delivery performance
- shorter lead time
- sufficient weekly capacity
- higher sourcing cost

These alternatives will later be compared by the SupplyChainIQ agent.

---

# Governed Metrics

The raw dataset contains all source fields needed to later define these canonical metrics:

1. On-Time Delivery (OTD)
2. Fill Rate
3. Days of Inventory
4. Landed Cost
5. Lead Time
6. Inventory Turnover
7. Supplier Risk Score
8. Stockout Risk

The canonical definitions are intentionally **not implemented in the raw source layer**.

They will be formally documented in the metric catalog and encoded into the Snowflake Semantic View.

---

# Repository Structure

## Current

```text
SupplyChainIQ/
│
├── README.md
├── PHASE1_HANDOFF.md
│
└── sql/
    ├── 01_database.sql
    ├── 02_tables.sql
    ├── 03_seed_data.sql
    └── 04_data_validation.sql
```

## Planned

As development continues, the repository will evolve toward:

```text
SupplyChainIQ/
│
├── README.md
├── AGENTS.md
├── PHASE1_HANDOFF.md
│
├── docs/
│   ├── architecture.md
│   ├── ontology.md
│   ├── metric_catalog.md
│   ├── personas.md
│   ├── demo_script.md
│   └── evaluation.md
│
├── sql/
│   ├── 01_database.sql
│   ├── 02_tables.sql
│   ├── 03_seed_data.sql
│   ├── 04_data_validation.sql
│   ├── 05_curated_model.sql
│   └── 06_curated_validation.sql
│
├── semantic/
│   ├── supply_chain_semantic_view.yaml
│   └── verified_queries.yaml
│
├── agents/
│   └── supply_chain_agent/
│
├── skills/
│   ├── supplier_risk/
│   ├── inventory_risk/
│   ├── impact_analysis/
│   └── scenario_analysis/
│
├── streamlit/
│   ├── app.py
│   ├── pages/
│   └── components/
│
├── mcp/
│   └── supply_chain_actions/
│
└── evaluation/
    ├── benchmark.csv
    └── results/
```

---

# SQL Scripts

## `sql/01_database.sql`

Creates:

- `SUPPLYCHAINIQ_DB`
- source schemas
- `CURATED`
- dataset metadata
- fixed dataset anchor date
- generation-support objects

## `sql/02_tables.sql`

Creates the Phase 1 source-system tables.

## `sql/03_seed_data.sql`

Generates the deterministic synthetic enterprise dataset using set-based Snowflake SQL.

It contains:

- normal business distributions
- deliberate data-quality variation
- flagship scenario
- alternate supplier scenario
- interplant transfer scenario
- supplier-risk scenarios
- inventory-risk scenarios

## `sql/04_data_validation.sql`

Validates:

- row counts
- canonical identifiers
- referential integrity
- duplicate grains
- shipment distributions
- inventory/demand alignment
- flagship scenario
- intervention feasibility
- metric source readiness
- controlled enterprise fragmentation

---

# Reproducing Phase 1

A developer using another Snowflake account should first inspect their environment and select an appropriate small warehouse.

Then execute the SQL scripts in order:

```text
01_database.sql
      ↓
02_tables.sql
      ↓
03_seed_data.sql
      ↓
04_data_validation.sql
```

The validation script must pass before moving to Phase 2.

Environment-specific settings such as warehouse name may need to be adjusted.

Do not change:

- dataset anchor date
- canonical IDs
- flagship scenario
- generation logic
- source-system mappings
- validation expectations

unless the team explicitly agrees to change the Phase 1 contract.

---

# Important Development Rules

## Do not rename raw source columns

The naming differences between ERP, TMS, WMS, Planning, CRM and Supplier Portal are intentional.

## Do not break canonical identifiers

Stable supplier, part, plant, shipment, order and customer IDs allow deterministic harmonization.

## Do not hard-code demo answers

Results such as the 2,150-unit shortage must remain derivable from source facts.

## Do not redefine canonical metrics independently

Metric definitions will be maintained centrally through the metric catalog and Semantic View.

## Do not compare currencies directly

Some source purchasing/logistics data uses different currencies.

A governed FX normalization layer must be introduced before cross-currency cost comparisons.

## Do not skip directly to the agent

The intended architecture is:

```text
Data
 ↓
Ontology
 ↓
Canonical CURATED Model
 ↓
Semantic View
 ↓
Cortex Analyst / Cortex Search
 ↓
Cortex Agent
 ↓
Streamlit / Actions
```

---

# Phase 1 Validation

Phase 1 validation reported:

```text
23 / 23 referential checks passed
Canonical orphan count = 0
Duplicate business grains = 0
```

The flagship scenario also passed all required calculations.

See:

```text
PHASE1_HANDOFF.md
```

for the detailed Phase 1 completion report and developer handoff.

---

# Next Phase

## Phase 2 — Ontology + Canonical CURATED Model

Phase 2 will define:

- canonical business entities
- keys
- relationships
- cardinalities
- hierarchies
- source mappings
- business metric definitions
- persona terminology
- FX normalization strategy

Expected Phase 2 files include:

```text
docs/ontology.md
docs/metric_catalog.md
docs/personas.md

sql/05_curated_model.sql
sql/06_curated_validation.sql
```

Only after Phase 2 validation should the project move to the Snowflake Semantic View.

---

# Team Collaboration

GitHub is the source of truth for project artifacts.

Recommended workflow:

```text
main
│
├── phase2-ontology-curated
├── phase3-semantic-view
├── phase4-analyst-search
├── phase5-agent
├── phase6-streamlit
└── phase7-evaluation
```

Each phase owner should:

1. Pull the latest `main`.
2. Create/use the appropriate feature branch.
3. Reproduce prerequisite Snowflake objects if necessary.
4. Implement the phase.
5. Validate it.
6. Commit all reproducible project artifacts.
7. Push the branch.
8. Open a pull request.
9. Merge only after review.

No important implementation should exist solely in one developer's Snowflake account.

---

# Current Phase Status

| Phase | Status |
|---|---|
| Synthetic Data Foundation | ✅ Complete |
| Ontology | ⏳ Next |
| Canonical CURATED Model | ⏳ Next |
| Semantic View | Not started |
| Cortex Analyst | Not started |
| Cortex Search | Not started |
| Cortex Agent | Not started |
| Agent Skills | Not started |
| Streamlit Control Tower | Not started |
| MCP Action Layer | Not started |
| Evaluation | Not started |

---

## SupplyChainIQ

**One governed semantic truth for Planning, Procurement and Logistics — from fragmented supply-chain data to explainable, controlled action.**