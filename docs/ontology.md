# SupplyChainIQ — Canonical Business Ontology (Phase 2)

This document defines the canonical business entities exposed by `SUPPLYCHAINIQ_DB.CURATED`.
CURATED is a **read-only, view-only** layer over the Phase 1 source-system tables. It performs
no physical data duplication and no aggregation of transaction/fact grains — it only renames and
lightly joins existing columns into a single canonical vocabulary.

Canonical identifiers used across the ontology:
- `SUPPLIER_ID` — canonical supplier identifier
- `PART_ID` — canonical part identifier
- `PLANT_ID` — canonical plant identifier
- `CUSTOMER_ID` — canonical customer identifier
- `CARRIER_ID` — canonical carrier identifier

No Product or BOM entity is defined — Phase 1 data is part-centric and contains no bill-of-materials
or product-hierarchy structure above `PRODUCT_FAMILY` / `PRODUCT_CATEGORY` on `MATERIAL_MASTER`.

---

## Supplier

- **Business definition:** A vendor/supplier that can supply parts, sourced from the ERP vendor
  master and enriched with supplier-portal profile attributes.
- **Canonical key:** `SUPPLIER_ID`
- **Grain:** one row per supplier.
- **Source table(s):** `SAP_ERP.VENDOR_MASTER` (primary, system of record for identity and name),
  `SUPPLIER_PORTAL.SUPPLIER_PROFILE` (LEFT JOIN, portal attributes only).
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `SUPPLIER_ID` | `VENDOR_MASTER.VENDOR_ID` |
  | `SUPPLIER_NAME` | `VENDOR_MASTER.VENDOR_NAME` |
  | `SUPPLIER_NAME_PORTAL` | `SUPPLIER_PROFILE.SUPPLIER_NAME` (preserved separately, not reconciled) |
  | `REGION`, `COUNTRY`, `COUNTRY_CODE` | `VENDOR_MASTER.REGION`, `.COUNTRY`, `.COUNTRY_CODE` |
  | `VENDOR_TIER` | `VENDOR_MASTER.VENDOR_TIER` |
  | `VENDOR_STATUS` | `VENDOR_MASTER.VENDOR_STATUS` |
  | `PAYMENT_TERMS` | `VENDOR_MASTER.PAYMENT_TERMS` |
  | `DEFAULT_CURRENCY` | `VENDOR_MASTER.DEFAULT_CURRENCY` |
  | `CREATED_DATE` | `VENDOR_MASTER.CREATED_DATE` |
  | `SUPPLIER_COUNTRY_PORTAL` | `SUPPLIER_PROFILE.SUPPLIER_COUNTRY` |
  | `PORTAL_STATUS` | `SUPPLIER_PROFILE.PORTAL_STATUS` |
  | `ONBOARDED_ON` | `SUPPLIER_PROFILE.ONBOARDED_ON` |
  | `PRIMARY_CONTACT_ROLE` | `SUPPLIER_PROFILE.PRIMARY_CONTACT_ROLE` |
  | `HAS_PORTAL_PROFILE` | derived: `SUPPLIER_PROFILE.SUPPLIER_ID IS NOT NULL` |
- **Relationships:** 1 → N Supplier-Part, 1 → N Purchase Order Line, 1 → N Supplier Performance.
- **Cardinality:** Supplier 1 → N Purchase Order Line; Supplier N ↔ N Part (via Supplier-Part).
- **Supported hierarchy:** `Global → REGION → COUNTRY → SUPPLIER`.
- **Lineage notes:** `SUPPLIER_ID` is the sole join key — no fuzzy name matching is used or needed.
  ERP is treated as the system of record for canonical `SUPPLIER_NAME`; the portal's differently
  formatted name is preserved verbatim as `SUPPLIER_NAME_PORTAL` for traceability. Monthly
  `SUPPLIER_SCORECARDS` are **not** joined here — see Supplier Performance below.

---

## Part

- **Business definition:** A purchasable/stockable material.
- **Canonical key:** `PART_ID`
- **Grain:** one row per part.
- **Source table(s):** `SAP_ERP.MATERIAL_MASTER`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `PART_ID` | `MATERIAL_NO` |
  | `PART_DESCRIPTION` | `MATERIAL_DESCRIPTION` |
  | `PRODUCT_FAMILY` | `PRODUCT_FAMILY` |
  | `PRODUCT_CATEGORY` | `PRODUCT_CATEGORY` |
  | `UNIT_OF_MEASURE`, `STANDARD_COST`, `WEIGHT`, `CRITICALITY`, `ACTIVE_FLAG` | passthrough |
- **Relationships:** 1 → N Supplier-Part, 1 → N Purchase Order Line, 1 → N Inventory Snapshot,
  1 → N Demand, 1 → N Customer Order Line.
- **Cardinality:** Part N ↔ N Supplier (via Supplier-Part).
- **Supported hierarchy:** `PRODUCT_FAMILY → PRODUCT_CATEGORY → PART`.
- **Lineage notes:** No BOM/Product entity invented — this is the terminal level of the part
  hierarchy present in Phase 1.

---

## Plant

- **Business definition:** A physical manufacturing/distribution site.
- **Canonical key:** `PLANT_ID`
- **Grain:** one row per plant.
- **Source table(s):** `SAP_ERP.PLANT_MASTER`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `PLANT_ID` | `PLANT_CODE` |
  | `PLANT_NAME`, `REGION`, `COUNTRY`, `CAPACITY`, `PLANT_TYPE`, `ACTIVE_FLAG` | passthrough |
- **Relationships:** 1 → N Purchase Order Line, 1 → N Inventory Snapshot, 1 → N Demand,
  1 → N Customer Order Line (as fulfillment site), 1 → N Transport Option (destination),
  1 → N Interplant Transfer Option (origin and destination).
- **Cardinality:** one-to-many in every direction listed above.
- **Supported hierarchy:** `Global → REGION → COUNTRY → PLANT`.
- **Lineage notes:** none.

---

## Supplier-Part

- **Business definition:** An approved sourcing agreement — which supplier may supply which part,
  and at what price/lead-time/capacity.
- **Canonical key:** `(SUPPLIER_ID, PART_ID)`
- **Grain:** one row per approved supplier × part sourcing agreement.
- **Source table(s):** `SAP_ERP.SUPPLIER_MATERIAL`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `SUPPLIER_ID` | `VENDOR_ID` |
  | `PART_ID` | `MATERIAL_NO` |
  | `IS_PRIMARY_SUPPLIER`, `AGREED_UNIT_PRICE`, `CONTRACT_LEAD_TIME_DAYS`, `MINIMUM_ORDER_QTY`, `MAX_WEEKLY_SUPPLY_QTY`, `CURRENCY`, `VALID_FROM`, `VALID_TO` | passthrough |
- **Relationships:** bridges Supplier and Part (M:N).
- **Cardinality:** `Supplier N ↔ N Part`.
- **Supported hierarchy:** none (bridge entity).
- **Lineage notes:** `CURRENCY` preserved unconverted per agreement — agreements can be priced in
  different currencies across suppliers; never aggregate `AGREED_UNIT_PRICE` across rows without
  filtering to one currency.

---

## Purchase Order Line

- **Business definition:** One line of an inbound purchase order to a supplier.
- **Canonical key:** `(PO_NUMBER, PO_LINE_NUMBER)`
- **Grain:** one row per PO line.
- **Source table(s):** `SAP_ERP.PURCHASE_ORDER_LINES`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `SUPPLIER_ID` | `VENDOR_ID` |
  | `PART_ID` | `MATERIAL_NO` |
  | `PLANT_ID` | `PLANT_CODE` |
  | `PO_NUMBER`, `PO_LINE_NUMBER`, `ORDER_DATE`, `CONFIRMATION_DATE`, `PROMISED_DATE`, `ORDER_QTY`, `UNIT_PRICE`, `CURRENCY`, `PO_STATUS` | passthrough |
- **Relationships:** Supplier 1 → N; Part 1 → N; Plant 1 → N; PO Line 1 → N Shipment.
- **Cardinality:** one PO line may be fulfilled by multiple shipment lines.
- **Supported hierarchy:** calendar (`Year → Quarter → Month → Week → Day`) on date fields.
- **Lineage notes:** `CANCELLED` PO lines are retained (not filtered) — governed OTD/exclusion
  logic is a downstream metrics concern, not a curation concern. `CURRENCY` preserved unconverted.

---

## Shipment

- **Business definition:** One inbound shipment line fulfilling a purchase order line.
- **Canonical key:** `(SHIPMENT_ID, SHIPMENT_LINE_NUMBER)`
- **Grain:** one row per shipment line.
- **Source table(s):** `TMS_LOGISTICS.SHIPMENTS`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `SUPPLIER_ID` | `SUPPLIER_CODE` |
  | `PART_ID` | `ITEM_CODE` |
  | `PLANT_ID` | `DESTINATION_SITE` |
  | `CARRIER_ID` | `CARRIER_CODE` |
  | `PO_NUMBER` | `PO_REF` |
  | `PO_LINE_NUMBER` | `PO_LINE_REF` |
  | `SHIPMENT_ID`, `SHIPMENT_LINE_NUMBER`, `SHIP_DATE`, `EXPECTED_DELIVERY_DATE`, `ACTUAL_DELIVERY_DATE`, `PROJECTED_DELIVERY_DATE`, `SHIPPED_QTY`, `RECEIVED_QTY`, `FREIGHT_COST`, `DUTY_COST`, `HANDLING_COST`, `OTHER_LOGISTICS_COST`, `TRANSPORT_MODE`, `SHIPMENT_STATUS` | passthrough |
- **Relationships:** N → 1 Purchase Order Line; N → 1 Carrier.
- **Cardinality:** many Shipments may fulfil one PO Line.
- **Supported hierarchy:** calendar on date fields.
- **Lineage notes:** all four logistics cost components (`FREIGHT_COST`, `DUTY_COST`,
  `HANDLING_COST`, `OTHER_LOGISTICS_COST`) are landed-cost facts in the PO's `CURRENCY` — no
  currency column exists directly on `SHIPMENTS`; join to `PURCHASE_ORDER_LINE` for currency
  context if needed, do not assume a single global currency.

---

## Inventory Snapshot

- **Business definition:** A weekly on-hand/available inventory position for a part at a plant.
- **Canonical key:** `(PART_ID, PLANT_ID, SNAPSHOT_DATE)`
- **Grain:** `Inventory Snapshot = one Part × one Plant × one Snapshot Date`.
- **Source table(s):** `WMS_INVENTORY.INVENTORY_SNAPSHOTS`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `PART_ID` | `SKU` |
  | `PLANT_ID` | `SITE_ID` |
  | `SNAPSHOT_DATE`, `ON_HAND_QTY`, `RESERVED_QTY`, `AVAILABLE_QTY`, `SAFETY_STOCK_QTY`, `IN_TRANSIT_QTY`, `INVENTORY_STATUS` | passthrough |
- **Relationships:** Part 1 → N; Plant 1 → N.
- **Cardinality:** one-to-many from Part and from Plant.
- **Supported hierarchy:** calendar on `SNAPSHOT_DATE`.
- **Lineage notes:** weekly cadence; latest snapshot date = dataset anchor date. No unit-price
  column — do not fabricate a monetary inventory value here.

---

## Demand

- **Business definition:** Daily forecast and actual demand for a part at a plant/location.
- **Canonical key:** `(PART_ID, PLANT_ID, DEMAND_DATE)`
- **Grain:** `Demand = one Part × one Plant × one Demand Date`.
- **Source table(s):** `DEMAND_PLANNING.DEMAND_HISTORY`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `PART_ID` | `PART_ID` (already canonical) |
  | `PLANT_ID` | `LOCATION_ID` |
  | `DEMAND_DATE`, `FORECAST_QTY`, `ACTUAL_DEMAND_QTY`, `FORECAST_VERSION`, `DEMAND_SOURCE`, `DEMAND_PATTERN` | passthrough |
- **Relationships:** Part 1 → N; Plant 1 → N.
- **Cardinality:** one-to-many from Part and from Plant.
- **Supported hierarchy:** calendar on `DEMAND_DATE`.
- **Lineage notes:** none.

---

## Customer

- **Business definition:** A business customer that places orders.
- **Canonical key:** `CUSTOMER_ID`
- **Grain:** one row per customer.
- **Source table(s):** `CRM_ORDERS.CUSTOMER_MASTER`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `CUSTOMER_ID`, `CUSTOMER_NAME`, `CUSTOMER_SEGMENT`, `REGION`, `COUNTRY`, `PRIORITY_TIER`, `ACTIVE_FLAG` | passthrough (already canonical) |
- **Relationships:** 1 → N Customer Order Line.
- **Cardinality:** one-to-many.
- **Supported hierarchy:** `Global → REGION → COUNTRY → CUSTOMER`.
- **Lineage notes:** synthetic company-style names only, no person-level PII.

---

## Customer Order Line

- **Business definition:** One line of an outbound customer order.
- **Canonical key:** `(ORDER_ID, ORDER_LINE)`
- **Grain:** one row per customer order line.
- **Source table(s):** `CRM_ORDERS.CUSTOMER_ORDER_LINES`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `PART_ID` | `PART_NUMBER` |
  | `PLANT_ID` | `FULFILLMENT_SITE` |
  | `CUSTOMER_ID`, `ORDER_ID`, `ORDER_LINE`, `ORDER_DATE`, `REQUESTED_DATE`, `DUE_DATE`, `ORDERED_QTY`, `FULFILLED_QTY`, `UNIT_SELL_PRICE`, `ORDER_VALUE`, `ORDER_STATUS`, `PRIORITY` | passthrough |
- **Relationships:** Customer 1 → N; Part 1 → N; Plant 1 → N (as fulfillment site).
- **Cardinality:** one-to-many from Customer, Part, and Plant.
- **Supported hierarchy:** calendar on date fields.
- **Lineage notes:** `ORDER_VALUE` is denominated in INR (per Phase 1 dataset metadata) — do not
  mix with PO/shipment costs, which are in vendor default currency, when aggregating monetary
  totals. Fill Rate is intentionally not precomputed here — a metrics-layer concern.

---

## Carrier

- **Business definition:** A transportation carrier used to move shipments.
- **Canonical key:** `CARRIER_ID`
- **Grain:** one row per carrier.
- **Source table(s):** `TMS_LOGISTICS.CARRIER_MASTER`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `CARRIER_ID` | `CARRIER_CODE` |
  | `CARRIER_NAME`, `TRANSPORT_MODE`, `REGION`, `SERVICE_LEVEL`, `ACTIVE_FLAG` | passthrough |
- **Relationships:** 1 → N Shipment.
- **Cardinality:** one-to-many.
- **Supported hierarchy:** none beyond `REGION`.
- **Lineage notes:** none.

---

## Supplier Performance

- **Business definition:** Monthly supplier scorecard capturing delivery, quality, and service
  risk.
- **Canonical key:** `(SUPPLIER_ID, SCORECARD_DATE)`
- **Grain:** `Supplier Performance = one Supplier × one Scorecard Month`.
- **Source table(s):** `SUPPLIER_PORTAL.SUPPLIER_SCORECARDS`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `SUPPLIER_ID`, `SCORECARD_DATE`, `QUALITY_SCORE`, `REJECTION_RATE`, `REPORTED_LEAD_TIME_DAYS`, `LEAD_TIME_VARIABILITY`, `SERVICE_SCORE`, `RISK_CATEGORY`, `OPEN_ISSUE_COUNT` | passthrough (already canonical) |
- **Relationships:** Supplier 1 → N.
- **Cardinality:** one-to-many (12 rows per supplier).
- **Supported hierarchy:** calendar on `SCORECARD_DATE`.
- **Lineage notes:** **Deliberately kept as a separate, time-grained fact.** Never flattened into
  `CURATED.SUPPLIER` (which stays one-row-per-supplier). Risk is multidimensional (delivery,
  quality, service are independent) — do not collapse into a single derived score in this layer.

---

## Transport Option

- **Business definition:** A region-to-plant transport lane catalogue entry (normal vs. expedited).
- **Canonical key:** `(ORIGIN_REGION, DESTINATION_PLANT_ID, TRANSPORT_MODE)`
- **Grain:** one row per origin-region × destination-plant × transport-mode lane.
- **Source table(s):** `TMS_LOGISTICS.TRANSPORT_OPTIONS`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `DESTINATION_PLANT_ID` | `DESTINATION_PLANT` |
  | `ORIGIN_REGION`, `TRANSPORT_MODE`, `NORMAL_TRANSIT_DAYS`, `EXPEDITED_TRANSIT_DAYS`, `NORMAL_COST_FACTOR`, `EXPEDITE_COST_FACTOR`, `ACTIVE_FLAG` | passthrough |
- **Relationships:** Plant 1 → N (destination side only).
- **Cardinality:** one-to-many from Plant (destination).
- **Supported hierarchy:** none.
- **Lineage notes:** **Origin remains a REGION, not a Plant** — this is a real structural
  asymmetry vs. Interplant Transfer Option and must not be forced into a plant-to-plant shape.

---

## Interplant Transfer Option

- **Business definition:** A plant-to-plant stock-transfer lane.
- **Canonical key:** `(ORIGIN_PLANT_ID, DESTINATION_PLANT_ID, TRANSPORT_MODE)`
- **Grain:** one row per origin-plant × destination-plant × transport-mode lane.
- **Source table(s):** `TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS`.
- **Source-to-canonical mapping:**
  | Canonical | Source |
  |---|---|
  | `ORIGIN_PLANT_ID` | `ORIGIN_PLANT` |
  | `DESTINATION_PLANT_ID` | `DESTINATION_PLANT` |
  | `TRANSPORT_MODE`, `TRANSIT_DAYS`, `COST_PER_UNIT`, `FIXED_TRANSFER_COST`, `MAX_TRANSFER_QTY`, `ACTIVE_FLAG` | passthrough |
- **Relationships:** Plant 1 → N (origin side); Plant 1 → N (destination side).
- **Cardinality:** one-to-many from Plant in both directions.
- **Supported hierarchy:** none.
- **Lineage notes:** **Remains strictly Plant → Plant** (unlike Transport Option, which is
  Region → Plant).

---

## Entities intentionally excluded from CURATED

- **Supplier Documents** (`DOCUMENTS.SUPPLIER_DOCUMENTS`) — remains outside CURATED. It is
  unstructured content (contracts, SLAs, policies) referenced by `SUPPLIER_ID`, reserved for
  future Cortex Search indexing rather than relational curation.
- **`PUBLIC.DATASET_METADATA`, `PUBLIC.PART_SITE_COVERAGE`** — generation infrastructure, not
  business entities. Not curated.
- **Product / BOM entities** — not invented; Phase 1 data has no bill-of-materials structure.
