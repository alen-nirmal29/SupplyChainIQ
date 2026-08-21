/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 3B / 4B / 4C : GOVERNED SEMANTIC VIEW + VERIFIED QUERY REPOSITORY
   FILE    : supply_chain_semantic_view.sql
   PURPOSE : Create the single governed Semantic View that Cortex Analyst and
             Cortex Agents will use to answer supply-chain business questions,
             and register the Phase 4B Verified Query Repository (15 VQs).

   SAFETY  : This script ONLY creates SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW.
             It reads from the 12 validated CURATED views (never Phase 1 source
             tables directly) and performs no DDL/DML against any Phase 1 or
             Phase 2 object. Uses CREATE OR REPLACE SEMANTIC VIEW (not
             CREATE OR ALTER) so it is safely rerunnable without depending on
             Preview alter semantics. COPY GRANTS preserves existing privilege
             grants across the replacement.

   PHASE 4C NOTE: Cortex Analyst evaluation run "phase4c_baseline_v1" failed
   with Snowflake error 392700 ("Metric FILL_RATE_PERCENT does not contain an
   aggregation function"). Root cause: supplier_otd_percent,
   shipment_schedule_adherence_percent, and fill_rate_percent were each
   defined as a bare division of two other declared metrics with no aggregate
   function of their own - valid for direct SEMANTIC_VIEW() execution (which
   resolves metric references transitively) but rejected by Cortex Analyst's
   stricter evaluation-time semantic-model validation. Fix: all three are now
   self-contained COUNT_IF/COUNT_IF or SUM/SUM ratios with the aggregate
   functions inlined directly in the metric's own expression. Formulas,
   eligibility rules, governance, and numeric results are unchanged. The
   now-unused-by-these-three private helper metrics (eligible_delivery_count,
   on_time_delivery_count, schedule_adherent_count, eligible_ordered_qty,
   eligible_fulfilled_qty) are intentionally retained. See
   sql/09_evaluation_compatibility_validation.sql.

   PHASE 4C NOTE (attempt #2): Evaluation run "phase4c_baseline_v2" failed
   with error 392700 ("Join relationship CUST_ORDER_LINE_TO_CUSTOMER using
   join key customer_id which is not defined in logical table
   cust_order_line"). Root cause (audited across ALL 15 relationships, not
   just this one): every FK-holding ("many") side of every relationship was
   missing its own join-key column as an explicit dimension - only the
   referenced ("one") side already exposed it. Native SEMANTIC_VIEW() DDL and
   queries compiled fine because the relationship can resolve directly
   against the physical base-table column, but the YAML representation used
   by Cortex Analyst Evaluation requires every relationship join key to exist
   as a defined field in its logical table. Fix: added 16 explicit technical
   relationship-key dimensions (supplier_part.supplier_id/part_id,
   po_line.supplier_id/part_id/plant_id, shipment.po_number/po_line_number/
   carrier_id, inv.part_id/plant_id, demand.part_id/plant_id,
   cust_order_line.customer_id/part_id/plant_id, supplier_perf.supplier_id) -
   one per missing join key, each a plain passthrough of the physical FK
   column with no synonyms, so they do not compete with the canonical
   business dimensions on the referenced tables. Dimension count: 54 -> 70.

   PHASE 4B NOTE: AI_VERIFIED_QUERIES adds 15 Verified Queries (VQ01-VQ15) as
   ground truth for Cortex Analyst. VQ03 is registered with
   ONBOARDING_QUESTION FALSE and is intentionally excluded from the Phase 4C
   formal evaluation set (see docs/verified_query_catalog.md) - it exists only
   to teach business-language phrasing equivalence with VQ02 at runtime. No
   logical tables, relationships, dimensions, facts, or metrics were changed
   to accommodate these Verified Queries.

   SCOPE   : 12 of the 14 CURATED views (TRANSPORT_OPTION and
             INTERPLANT_TRANSFER_OPTION are intentionally excluded - they
             remain CURATED decision-support inputs for future Agent Skills).

   GOVERNANCE NOTE (Phase 3A revision, locked):
     - Canonical Supplier OTD compares SHIPMENT.ACTUAL_DELIVERY_DATE to the
       parent PURCHASE_ORDER_LINE.PROMISED_DATE (the original supplier
       commitment) - NOT SHIPMENT.EXPECTED_DELIVERY_DATE.
     - Shipment Schedule Adherence (a distinct, non-canonical-OTD concept)
       compares ACTUAL_DELIVERY_DATE to EXPECTED_DELIVERY_DATE.
     - Actual Landed Cost uses each shipment line's own RECEIVED_QTY (never
       the parent PO line's ORDER_QTY) to avoid duplicating purchase cost
       across split shipments.
     - No unsafe independent fact-to-fact relationships are exposed; the
       intentional Purchase Order Line -> Shipment 1:N business relationship
       is retained.
     - No relationship exists between Inventory Snapshot and Demand (they are
       independent facts at different, incompatible grains sharing only
       PART_ID/PLANT_ID - Demand is not unique on those columns alone, so no
       valid REFERENCES relationship could be declared even if desired).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE SEMANTIC VIEW SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW

  TABLES (
    supplier AS SUPPLYCHAINIQ_DB.CURATED.SUPPLIER
      PRIMARY KEY (SUPPLIER_ID)
      WITH SYNONYMS ('vendor', 'vendor company', 'source supplier')
      COMMENT = 'Canonical Supplier: one row per SUPPLIER_ID, harmonized from ERP (identity) and the supplier portal (profile). Monthly scorecards live separately in supplier_perf.',

    part AS SUPPLYCHAINIQ_DB.CURATED.PART
      PRIMARY KEY (PART_ID)
      WITH SYNONYMS ('material', 'component', 'item', 'SKU')
      COMMENT = 'Canonical Part: one row per PART_ID.',

    plant AS SUPPLYCHAINIQ_DB.CURATED.PLANT
      PRIMARY KEY (PLANT_ID)
      WITH SYNONYMS ('site', 'facility')
      COMMENT = 'Canonical Plant: one row per PLANT_ID.',

    supplier_part AS SUPPLYCHAINIQ_DB.CURATED.SUPPLIER_PART
      PRIMARY KEY (SUPPLIER_ID, PART_ID)
      WITH SYNONYMS ('approved sourcing', 'supplier sourcing agreement')
      COMMENT = 'Canonical Supplier-Part bridge: one row per approved SUPPLIER_ID x PART_ID sourcing agreement.',

    po_line AS SUPPLYCHAINIQ_DB.CURATED.PURCHASE_ORDER_LINE
      PRIMARY KEY (PO_NUMBER, PO_LINE_NUMBER)
      WITH SYNONYMS ('purchase order', 'PO line', 'inbound order line')
      COMMENT = 'Canonical Purchase Order Line: one row per (PO_NUMBER, PO_LINE_NUMBER). PROMISED_DATE is the original supplier commitment used for canonical OTD.',

    shipment AS SUPPLYCHAINIQ_DB.CURATED.SHIPMENT
      PRIMARY KEY (SHIPMENT_ID, SHIPMENT_LINE_NUMBER)
      WITH SYNONYMS ('inbound shipment', 'delivery')
      COMMENT = 'Canonical Shipment: one row per (SHIPMENT_ID, SHIPMENT_LINE_NUMBER). A PO line may have multiple shipment lines (split delivery).',

    inv AS SUPPLYCHAINIQ_DB.CURATED.INVENTORY_SNAPSHOT
      PRIMARY KEY (PART_ID, PLANT_ID, SNAPSHOT_DATE)
      WITH SYNONYMS ('stock', 'inventory position', 'on-hand stock')
      COMMENT = 'Canonical Inventory Snapshot: one row per Part x Plant x weekly Snapshot Date.',

    demand AS SUPPLYCHAINIQ_DB.CURATED.DEMAND
      PRIMARY KEY (PART_ID, PLANT_ID, DEMAND_DATE)
      WITH SYNONYMS ('forecast', 'demand history')
      COMMENT = 'Canonical Demand: one row per Part x Plant x daily Demand Date.',

    customer AS SUPPLYCHAINIQ_DB.CURATED.CUSTOMER
      PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS ('account', 'buyer', 'client')
      COMMENT = 'Canonical Customer: one row per CUSTOMER_ID.',

    cust_order_line AS SUPPLYCHAINIQ_DB.CURATED.CUSTOMER_ORDER_LINE
      PRIMARY KEY (ORDER_ID, ORDER_LINE)
      WITH SYNONYMS ('customer order', 'sales order line')
      COMMENT = 'Canonical Customer Order Line: one row per (ORDER_ID, ORDER_LINE).',

    carrier AS SUPPLYCHAINIQ_DB.CURATED.CARRIER
      PRIMARY KEY (CARRIER_ID)
      WITH SYNONYMS ('freight carrier', 'logistics provider')
      COMMENT = 'Canonical Carrier: one row per CARRIER_ID.',

    supplier_perf AS SUPPLYCHAINIQ_DB.CURATED.SUPPLIER_PERFORMANCE
      PRIMARY KEY (SUPPLIER_ID, SCORECARD_DATE)
      WITH SYNONYMS ('supplier scorecard', 'vendor scorecard')
      COMMENT = 'Canonical Supplier Performance: one row per Supplier x monthly Scorecard Date. Deliberately kept separate from supplier (one-row-per-supplier) - never flattened.'
  )

  RELATIONSHIPS (
    supplier_part_to_supplier AS supplier_part (SUPPLIER_ID) REFERENCES supplier,
    supplier_part_to_part AS supplier_part (PART_ID) REFERENCES part,
    po_line_to_supplier AS po_line (SUPPLIER_ID) REFERENCES supplier,
    po_line_to_part AS po_line (PART_ID) REFERENCES part,
    po_line_to_plant AS po_line (PLANT_ID) REFERENCES plant,
    shipment_to_po_line AS shipment (PO_NUMBER, PO_LINE_NUMBER) REFERENCES po_line,
    shipment_to_carrier AS shipment (CARRIER_ID) REFERENCES carrier,
    inv_to_part AS inv (PART_ID) REFERENCES part,
    inv_to_plant AS inv (PLANT_ID) REFERENCES plant,
    demand_to_part AS demand (PART_ID) REFERENCES part,
    demand_to_plant AS demand (PLANT_ID) REFERENCES plant,
    cust_order_line_to_customer AS cust_order_line (CUSTOMER_ID) REFERENCES customer,
    cust_order_line_to_part AS cust_order_line (PART_ID) REFERENCES part,
    cust_order_line_to_plant AS cust_order_line (PLANT_ID) REFERENCES plant,
    supplier_perf_to_supplier AS supplier_perf (SUPPLIER_ID) REFERENCES supplier
  )

  FACTS (
    po_line.order_qty AS ORDER_QTY
      COMMENT = 'Row-level ordered quantity for a PO line.',
    po_line.unit_price AS UNIT_PRICE
      COMMENT = 'Row-level unit price for a PO line, in the PO line CURRENCY.',
    po_line.purchase_amount AS ORDER_QTY * UNIT_PRICE
      COMMENT = 'Row-level derived purchase amount (ORDER_QTY x UNIT_PRICE), in the PO line CURRENCY.',

    shipment.shipped_qty AS SHIPPED_QTY
      COMMENT = 'Row-level shipped quantity for a shipment line.',
    shipment.received_qty AS RECEIVED_QTY
      COMMENT = 'Row-level received quantity for a shipment line. Used (not PO ORDER_QTY) for Actual Landed Cost to avoid duplicating purchase cost across split shipments.',
    shipment.freight_cost AS FREIGHT_COST
      COMMENT = 'Row-level freight cost for a shipment line, in the parent PO line CURRENCY.',
    shipment.duty_cost AS DUTY_COST
      COMMENT = 'Row-level duty cost for a shipment line, in the parent PO line CURRENCY.',
    shipment.handling_cost AS HANDLING_COST
      COMMENT = 'Row-level handling cost for a shipment line, in the parent PO line CURRENCY.',
    shipment.other_logistics_cost AS OTHER_LOGISTICS_COST
      COMMENT = 'Row-level other logistics cost for a shipment line, in the parent PO line CURRENCY.',
    shipment.delivery_delay_days AS DATEDIFF(day, EXPECTED_DELIVERY_DATE, ACTUAL_DELIVERY_DATE)
      COMMENT = 'Row-level delay in days versus the shipment own expected delivery date. NULL when not yet delivered. Not the canonical OTD comparison (which uses the PO PROMISED_DATE).',

    inv.on_hand_qty AS ON_HAND_QTY
      COMMENT = 'Row-level on-hand quantity at a Part x Plant x Snapshot Date.',
    inv.available_qty AS AVAILABLE_QTY
      COMMENT = 'Row-level available quantity at a Part x Plant x Snapshot Date.',
    inv.safety_stock_qty AS SAFETY_STOCK_QTY
      COMMENT = 'Row-level safety stock quantity at a Part x Plant x Snapshot Date.',

    demand.forecast_qty AS FORECAST_QTY
      COMMENT = 'Row-level forecast demand quantity at a Part x Plant x Demand Date.',
    demand.actual_demand_qty AS ACTUAL_DEMAND_QTY
      COMMENT = 'Row-level actual demand quantity at a Part x Plant x Demand Date. Governed source for Days of Inventory demand component.',

    cust_order_line.ordered_qty AS ORDERED_QTY
      COMMENT = 'Row-level ordered quantity for a customer order line.',
    cust_order_line.fulfilled_qty AS FULFILLED_QTY
      COMMENT = 'Row-level fulfilled quantity for a customer order line.',
    cust_order_line.order_value AS ORDER_VALUE
      COMMENT = 'Row-level order value for a customer order line, denominated in INR.',

    supplier_perf.quality_score AS QUALITY_SCORE
      COMMENT = 'Row-level monthly quality score for a supplier.',
    supplier_perf.rejection_rate AS REJECTION_RATE
      COMMENT = 'Row-level monthly rejection rate for a supplier.',
    supplier_perf.reported_lead_time_days AS REPORTED_LEAD_TIME_DAYS
      COMMENT = 'Row-level monthly self-reported lead time (days) for a supplier, from the supplier portal.',
    supplier_perf.lead_time_variability AS LEAD_TIME_VARIABILITY
      COMMENT = 'Row-level monthly lead-time variability for a supplier.',
    supplier_perf.service_score AS SERVICE_SCORE
      COMMENT = 'Row-level monthly service score for a supplier.',
    supplier_perf.open_issue_count AS OPEN_ISSUE_COUNT
      COMMENT = 'Row-level monthly open issue count for a supplier.',

    supplier_part.contract_lead_time_days AS CONTRACT_LEAD_TIME_DAYS
      COMMENT = 'Row-level contractual lead time (days) agreed between a supplier and a part.',
    supplier_part.agreed_unit_price AS AGREED_UNIT_PRICE
      COMMENT = 'Row-level agreed contract unit price for a supplier-part sourcing agreement, in the sourcing agreement CURRENCY.'
  )

  DIMENSIONS (
    supplier.supplier_id AS SUPPLIER_ID WITH SYNONYMS = ('vendor id', 'vendor code') COMMENT = 'Canonical supplier identifier.',
    supplier.supplier_name AS SUPPLIER_NAME WITH SYNONYMS = ('vendor name') COMMENT = 'Canonical (ERP) supplier name.',
    supplier.region AS REGION COMMENT = 'Supplier geographic region.',
    supplier.country AS COUNTRY COMMENT = 'Supplier country.',
    supplier.vendor_tier AS VENDOR_TIER WITH SYNONYMS = ('supplier tier') COMMENT = 'Supplier sourcing tier (e.g., Preferred, Standard).',
    supplier.vendor_status AS VENDOR_STATUS WITH SYNONYMS = ('supplier status') COMMENT = 'Supplier active/inactive status.',
    supplier.default_currency AS DEFAULT_CURRENCY COMMENT = 'Supplier default transacting currency.',

    part.part_id AS PART_ID WITH SYNONYMS = ('material number', 'SKU') COMMENT = 'Canonical part identifier.',
    part.part_description AS PART_DESCRIPTION WITH SYNONYMS = ('material description', 'item description') COMMENT = 'Human-readable part name.',
    part.product_family AS PRODUCT_FAMILY COMMENT = 'Top-level part grouping.',
    part.product_category AS PRODUCT_CATEGORY COMMENT = 'Sub-level part grouping.',
    part.criticality AS CRITICALITY WITH SYNONYMS = ('part criticality') COMMENT = 'Business criticality tier of the part.',

    plant.plant_id AS PLANT_ID WITH SYNONYMS = ('plant code', 'site code') COMMENT = 'Canonical plant identifier.',
    plant.plant_name AS PLANT_NAME COMMENT = 'Human-readable plant name.',
    plant.region AS REGION COMMENT = 'Plant geographic region.',
    plant.country AS COUNTRY COMMENT = 'Plant country.',

    supplier_part.is_primary_supplier AS IS_PRIMARY_SUPPLIER COMMENT = 'Whether this supplier is the primary approved source for the part.',
    supplier_part.currency AS CURRENCY COMMENT = 'Currency of the supplier-part sourcing agreement pricing.',
    supplier_part.supplier_id AS SUPPLIER_ID COMMENT = 'Relationship key to Supplier (supplier_part_to_supplier).',
    supplier_part.part_id AS PART_ID COMMENT = 'Relationship key to Part (supplier_part_to_part).',

    po_line.po_number AS PO_NUMBER WITH SYNONYMS = ('PO', 'purchase order number') COMMENT = 'Purchase order number.',
    po_line.po_line_number AS PO_LINE_NUMBER COMMENT = 'Line number within the purchase order.',
    po_line.po_status AS PO_STATUS WITH SYNONYMS = ('purchase order status') COMMENT = 'OPEN, DELIVERED, PARTIALLY_DELIVERED, OVERDUE, or CANCELLED.',
    po_line.order_date AS ORDER_DATE COMMENT = 'Date the purchase order was placed.',
    po_line.promised_date AS PROMISED_DATE WITH SYNONYMS = ('promise date', 'supplier commitment date') COMMENT = 'Original supplier-committed delivery date. Authoritative comparison field for canonical Supplier OTD.',
    po_line.currency AS CURRENCY COMMENT = 'Currency of the purchase order line pricing and cost components. Required grouping dimension for any monetary aggregation.',
    po_line.supplier_id AS SUPPLIER_ID COMMENT = 'Relationship key to Supplier (po_line_to_supplier).',
    po_line.part_id AS PART_ID COMMENT = 'Relationship key to Part (po_line_to_part).',
    po_line.plant_id AS PLANT_ID COMMENT = 'Relationship key to Plant (po_line_to_plant).',

    shipment.shipment_id AS SHIPMENT_ID COMMENT = 'Shipment identifier.',
    shipment.shipment_line_number AS SHIPMENT_LINE_NUMBER COMMENT = 'Line number within the shipment.',
    shipment.shipment_status AS SHIPMENT_STATUS WITH SYNONYMS = ('delivery status') COMMENT = 'DELIVERED, PARTIAL, IN_TRANSIT, or PLANNED.',
    shipment.transport_mode AS TRANSPORT_MODE WITH SYNONYMS = ('mode of transport') COMMENT = 'Air, Ocean, Road, etc.',
    shipment.ship_date AS SHIP_DATE WITH SYNONYMS = ('dispatch date') COMMENT = 'Date the shipment was dispatched.',
    shipment.expected_delivery_date AS EXPECTED_DELIVERY_DATE COMMENT = 'Shipment-level logistics target delivery date. Used ONLY for Shipment Schedule Adherence, not canonical Supplier OTD.',
    shipment.projected_delivery_date AS PROJECTED_DELIVERY_DATE WITH SYNONYMS = ('ETA') COMMENT = 'Current forward-looking estimated delivery date (not a realized outcome).',
    shipment.actual_delivery_date AS ACTUAL_DELIVERY_DATE WITH SYNONYMS = ('delivery date') COMMENT = 'Date the shipment was actually delivered. Authoritative actual-outcome field for both OTD and Schedule Adherence.',
    shipment.po_number AS PO_NUMBER COMMENT = 'Relationship key to Purchase Order Line (shipment_to_po_line).',
    shipment.po_line_number AS PO_LINE_NUMBER COMMENT = 'Relationship key to Purchase Order Line (shipment_to_po_line).',
    shipment.carrier_id AS CARRIER_ID COMMENT = 'Relationship key to Carrier (shipment_to_carrier).',

    inv.snapshot_date AS SNAPSHOT_DATE WITH SYNONYMS = ('inventory date', 'as-of date') COMMENT = 'Date of the weekly inventory position.',
    inv.inventory_status AS INVENTORY_STATUS WITH SYNONYMS = ('stock status', 'stockout risk') COMMENT = 'Source-governed status: HEALTHY, AT_SAFETY, BELOW_SAFETY, STOCKOUT, or EXCESS. Canonical (categorical) Stockout Risk signal.',
    inv.part_id AS PART_ID COMMENT = 'Relationship key to Part (inv_to_part).',
    inv.plant_id AS PLANT_ID COMMENT = 'Relationship key to Plant (inv_to_plant).',

    demand.demand_date AS DEMAND_DATE WITH SYNONYMS = ('forecast date') COMMENT = 'Date of the daily demand record.',
    demand.demand_source AS DEMAND_SOURCE COMMENT = 'Statistical Forecast, ML Model, Sales Input, or Customer Commit.',
    demand.part_id AS PART_ID COMMENT = 'Relationship key to Part (demand_to_part).',
    demand.plant_id AS PLANT_ID COMMENT = 'Relationship key to Plant (demand_to_plant).',

    customer.customer_id AS CUSTOMER_ID COMMENT = 'Canonical customer identifier.',
    customer.customer_name AS CUSTOMER_NAME COMMENT = 'Customer name.',
    customer.customer_segment AS CUSTOMER_SEGMENT WITH SYNONYMS = ('customer type') COMMENT = 'Customer business segment.',
    customer.region AS REGION COMMENT = 'Customer geographic region.',
    customer.country AS COUNTRY COMMENT = 'Customer country.',
    customer.priority_tier AS PRIORITY_TIER WITH SYNONYMS = ('customer priority') COMMENT = 'Customer priority tier (e.g., Strategic P1).',

    cust_order_line.order_id AS ORDER_ID COMMENT = 'Customer order identifier.',
    cust_order_line.order_line AS ORDER_LINE COMMENT = 'Line number within the customer order.',
    cust_order_line.order_status AS ORDER_STATUS COMMENT = 'OPEN, FULFILLED, PARTIALLY_FULFILLED, OVERDUE, or CANCELLED.',
    cust_order_line.order_date AS ORDER_DATE COMMENT = 'Date the customer order was placed. Default period-attribution field for Fill Rate.',
    cust_order_line.due_date AS DUE_DATE WITH SYNONYMS = ('promise date') COMMENT = 'Customer-committed due date. Use for Fill Rate only when the question explicitly refers to due/committed period.',
    cust_order_line.priority AS PRIORITY COMMENT = 'Order-line priority.',
    cust_order_line.customer_id AS CUSTOMER_ID COMMENT = 'Relationship key to Customer (cust_order_line_to_customer).',
    cust_order_line.part_id AS PART_ID COMMENT = 'Relationship key to Part (cust_order_line_to_part).',
    cust_order_line.plant_id AS PLANT_ID COMMENT = 'Relationship key to Plant (cust_order_line_to_plant).',

    carrier.carrier_id AS CARRIER_ID COMMENT = 'Canonical carrier identifier.',
    carrier.carrier_name AS CARRIER_NAME COMMENT = 'Carrier name.',
    carrier.transport_mode AS TRANSPORT_MODE COMMENT = 'Carrier primary transport mode.',
    carrier.region AS REGION COMMENT = 'Carrier operating region.',

    supplier_perf.scorecard_date AS SCORECARD_DATE WITH SYNONYMS = ('scorecard month') COMMENT = 'Month of the supplier scorecard.',
    supplier_perf.risk_category AS RISK_CATEGORY WITH SYNONYMS = ('risk level', 'risk tier') COMMENT = 'Source-governed multidimensional supplier risk classification: Low, Medium, High, or Critical. Canonical Supplier Risk signal - no new score is computed.',
    supplier_perf.supplier_id AS SUPPLIER_ID COMMENT = 'Relationship key to Supplier (supplier_perf_to_supplier).'
  )

  METRICS (

    /* ---------------- Purchase Order Line metrics ---------------- */
    po_line.total_order_qty AS SUM(po_line.order_qty)
      COMMENT = 'Total ordered quantity across purchase order lines.',
    po_line.total_purchase_amount AS SUM(po_line.purchase_amount)
      COMMENT = 'Total purchase amount across purchase order lines, in PO line CURRENCY. Must be grouped by CURRENCY when aggregating beyond a single supplier.',

    /* ---------------- Supplier-Part metrics ---------------- */
    supplier_part.contract_lead_time_days_avg AS AVG(supplier_part.contract_lead_time_days)
      WITH SYNONYMS = ('contract lead time')
      COMMENT = 'Contract Lead Time: the agreed contractual lead time (days) between a supplier and a part. Distinct from Realized Lead Time and Reported Lead Time - never blend these three concepts.',

    /* ---------------- Shipment metrics: canonical OTD ---------------- */
    PRIVATE shipment.eligible_delivery_count AS
      COUNT_IF(
        shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
        AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
        AND po_line.PO_STATUS <> 'CANCELLED'
      )
      COMMENT = 'Private helper: count of shipment lines eligible for OTD / Schedule Adherence judgement (DELIVERED or PARTIAL, has an actual delivery date, parent PO not cancelled).',

    PRIVATE shipment.on_time_delivery_count AS
      COUNT_IF(
        shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
        AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
        AND po_line.PO_STATUS <> 'CANCELLED'
        AND shipment.ACTUAL_DELIVERY_DATE <= po_line.PROMISED_DATE
      )
      COMMENT = 'Private helper: count of eligible shipment lines delivered on or before the parent PO line PROMISED_DATE (the original supplier commitment).',

    shipment.supplier_otd_percent AS
      COUNT_IF(
        shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
        AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
        AND po_line.PO_STATUS <> 'CANCELLED'
        AND shipment.ACTUAL_DELIVERY_DATE <= po_line.PROMISED_DATE
      )
      / NULLIF(
          COUNT_IF(
            shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
            AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
            AND po_line.PO_STATUS <> 'CANCELLED'
          ), 0)
      WITH SYNONYMS = ('on-time delivery', 'supplier delivery performance', 'vendor delivery performance', 'on-time percentage')
      COMMENT = 'Canonical Supplier OTD: percentage of eligible inbound shipment lines delivered on or before the PARENT PO LINE PROMISED_DATE (the original supplier commitment) - NOT the shipment EXPECTED_DELIVERY_DATE. Ratio of aggregated counts; returns NULL when there are no eligible shipments. Phase 4C: rewritten as a self-contained COUNT_IF/COUNT_IF ratio (Snowflake error 392700 - a metric expression built only from other metric references, with no aggregate function of its own, is rejected by Cortex Analyst evaluation validation even though it executes fine via SEMANTIC_VIEW()). Formula and result unchanged from the private-helper-based version.',

    /* ---------------- Shipment metrics: Shipment Schedule Adherence (distinct from OTD) ---------------- */
    PRIVATE shipment.schedule_adherent_count AS
      COUNT_IF(
        shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
        AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
        AND po_line.PO_STATUS <> 'CANCELLED'
        AND shipment.ACTUAL_DELIVERY_DATE <= shipment.EXPECTED_DELIVERY_DATE
      )
      COMMENT = 'Private helper: count of eligible shipment lines delivered on or before their OWN shipment-level EXPECTED_DELIVERY_DATE.',

    shipment.shipment_schedule_adherence_percent AS
      COUNT_IF(
        shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
        AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
        AND po_line.PO_STATUS <> 'CANCELLED'
        AND shipment.ACTUAL_DELIVERY_DATE <= shipment.EXPECTED_DELIVERY_DATE
      )
      / NULLIF(
          COUNT_IF(
            shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL')
            AND shipment.ACTUAL_DELIVERY_DATE IS NOT NULL
            AND po_line.PO_STATUS <> 'CANCELLED'
          ), 0)
      WITH SYNONYMS = ('shipment schedule adherence', 'logistics on-time rate', 'shipment target adherence')
      COMMENT = 'Shipment Schedule Adherence: percentage of eligible shipment lines meeting their own (possibly re-planned) logistics target EXPECTED_DELIVERY_DATE. This is a logistics-execution KPI, NOT canonical Supplier OTD - do not use its synonyms interchangeably with Supplier OTD. Phase 4C: rewritten as a self-contained COUNT_IF/COUNT_IF ratio for Cortex Analyst evaluation compatibility (error 392700). Formula and result unchanged.',

    /* ---------------- Shipment metrics: Actual Landed Cost ---------------- */
    shipment.actual_landed_cost AS
      SUM(
        IFF(
          shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL'),
          (shipment.received_qty * po_line.UNIT_PRICE)
            + COALESCE(shipment.freight_cost, 0)
            + COALESCE(shipment.duty_cost, 0)
            + COALESCE(shipment.handling_cost, 0)
            + COALESCE(shipment.other_logistics_cost, 0),
          NULL
        )
      )
      WITH SYNONYMS = ('landed cost', 'all-in delivered cost', 'total inbound landed cost')
      COMMENT = 'Canonical Actual Landed Cost at shipment-line grain: (RECEIVED_QTY x parent PO UNIT_PRICE) + logistics costs, for DELIVERED/PARTIAL shipments only. Uses RECEIVED_QTY (never the parent PO ORDER_QTY) so split shipments never duplicate purchase cost. CURRENCY inherited from the parent PO line (po_line.CURRENCY) - never sum across multiple currencies; always group by po_line.currency unless already scoped to one supplier/currency.',

    /* ---------------- Shipment metrics: Realized Lead Time ---------------- */
    shipment.realized_lead_time_days_avg AS
      AVG(
        IFF(
          shipment.SHIPMENT_STATUS IN ('DELIVERED', 'PARTIAL'),
          DATEDIFF(day, po_line.ORDER_DATE, shipment.ACTUAL_DELIVERY_DATE),
          NULL
        )
      )
      WITH SYNONYMS = ('realized lead time', 'actual lead time')
      COMMENT = 'Realized Lead Time: actual days elapsed from PO ORDER_DATE to ACTUAL_DELIVERY_DATE, for delivered/partial shipments. Distinct from Contract Lead Time and Reported Lead Time - never blend these three concepts.',

    shipment.total_shipped_qty AS SUM(shipment.shipped_qty)
      COMMENT = 'Total shipped quantity across shipment lines.',
    shipment.total_received_qty AS SUM(shipment.received_qty)
      COMMENT = 'Total received quantity across shipment lines.',

    /* ---------------- Inventory Snapshot metrics: DOI component A (latest inventory) ---------------- */
    inv.latest_snapshot_date AS MAX(inv.SNAPSHOT_DATE)
      COMMENT = 'Latest available inventory snapshot date for the queried Part/Plant grouping. Safe additive MAX. Use together with inv.available_qty / inv.safety_stock_qty / inv.on_hand_qty (filtered WHERE snapshot_date = this value) to obtain current inventory - do not attempt a single-step latest-value metric (empirically confirmed unsafe with NON ADDITIVE BY in this Snowflake version).',
    inv.available_qty_metric AS MAX(inv.available_qty)
      WITH SYNONYMS = ('available inventory', 'available stock')
      COMMENT = 'Available quantity metric, queryable together with inv.snapshot_date. For current/latest inventory, filter to inv.latest_snapshot_date first (two-step pattern) - see Days of Inventory governance in docs/metric_catalog.md.',
    inv.on_hand_qty_metric AS MAX(inv.on_hand_qty)
      COMMENT = 'On-hand quantity metric, queryable together with inv.snapshot_date.',
    inv.safety_stock_qty_metric AS MAX(inv.safety_stock_qty)
      COMMENT = 'Safety stock quantity metric, queryable together with inv.snapshot_date.',

    /* ---------------- Demand metrics: DOI component B (trailing 30-day average demand) ---------------- */
    PRIVATE demand.daily_actual_demand AS SUM(demand.actual_demand_qty)
      COMMENT = 'Private helper: actual demand quantity at the Part x Plant x Demand Date grain (grain-unique, so SUM is the row value).',
    demand.avg_daily_demand_30d AS
      AVG(demand.daily_actual_demand) OVER (
        PARTITION BY EXCLUDING demand.demand_date
        ORDER BY demand.demand_date
        RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW
      )
      WITH SYNONYMS = ('30-day average demand', 'trailing 30-day demand')
      COMMENT = 'Governed Days-of-Inventory demand component: trailing 30-calendar-day average of ACTUAL_DEMAND_QTY ending on (and including) the queried demand_date, per Part/Plant. Requires demand.demand_date to be specified in the query (window-function metric requirement). Empirically validated against the Phase 1/2 governed baseline for Part P104 / Plant P01 (= 700). Combine with inv.available_qty_metric (at the corresponding latest snapshot date) for a governed two-step Days of Inventory calculation - not implemented as a single native metric because Inventory Snapshot and Demand cannot be safely related (Demand is not unique on PART_ID/PLANT_ID alone).',
    demand.total_forecast_qty AS SUM(demand.forecast_qty)
      COMMENT = 'Total forecast demand quantity.',
    demand.total_actual_demand_qty AS SUM(demand.actual_demand_qty)
      COMMENT = 'Total actual demand quantity.',

    /* ---------------- Customer Order Line metrics: canonical Fill Rate ---------------- */
    PRIVATE cust_order_line.eligible_ordered_qty AS
      SUM(IFF(cust_order_line.ORDER_STATUS <> 'CANCELLED', cust_order_line.ordered_qty, 0))
      COMMENT = 'Private helper: total ordered quantity excluding CANCELLED order lines.',
    PRIVATE cust_order_line.eligible_fulfilled_qty AS
      SUM(IFF(cust_order_line.ORDER_STATUS <> 'CANCELLED', cust_order_line.fulfilled_qty, 0))
      COMMENT = 'Private helper: total fulfilled quantity excluding CANCELLED order lines.',
    cust_order_line.fill_rate_percent AS
      SUM(IFF(cust_order_line.ORDER_STATUS <> 'CANCELLED', cust_order_line.fulfilled_qty, 0))
      / NULLIF(
          SUM(IFF(cust_order_line.ORDER_STATUS <> 'CANCELLED', cust_order_line.ordered_qty, 0)), 0)
      WITH SYNONYMS = ('fulfillment rate', 'order fulfillment', 'quantity fulfillment')
      COMMENT = 'Canonical Fill Rate: SUM(FULFILLED_QTY) / SUM(ORDERED_QTY), excluding CANCELLED order lines. Never average row-level percentages. Default period attribution is cust_order_line.order_date; use cust_order_line.due_date only when the question explicitly refers to due/committed period. Phase 4C: rewritten as a self-contained SUM/SUM ratio for Cortex Analyst evaluation compatibility (error 392700 - the prior version divided two other metric references with no aggregate of its own). Formula and result unchanged.',
    cust_order_line.total_ordered_qty AS SUM(cust_order_line.ordered_qty)
      COMMENT = 'Total ordered quantity across customer order lines (all statuses).',
    cust_order_line.total_fulfilled_qty AS SUM(cust_order_line.fulfilled_qty)
      COMMENT = 'Total fulfilled quantity across customer order lines (all statuses).',
    cust_order_line.total_order_value AS SUM(cust_order_line.order_value)
      WITH SYNONYMS = ('revenue exposure', 'order revenue')
      COMMENT = 'Total customer order value, denominated in INR.',

    /* ---------------- Supplier Performance metrics ---------------- */
    supplier_perf.quality_score_avg AS AVG(supplier_perf.quality_score)
      COMMENT = 'Average monthly quality score.',
    supplier_perf.rejection_rate_avg AS AVG(supplier_perf.rejection_rate)
      COMMENT = 'Average monthly rejection rate.',
    supplier_perf.reported_lead_time_days_avg AS AVG(supplier_perf.reported_lead_time_days)
      WITH SYNONYMS = ('reported lead time')
      COMMENT = 'Reported Lead Time: average self-reported monthly lead time (days) from the supplier portal. Distinct from Contract Lead Time and Realized Lead Time - never blend these three concepts.',
    supplier_perf.lead_time_variability_avg AS AVG(supplier_perf.lead_time_variability)
      COMMENT = 'Average monthly lead-time variability.',
    supplier_perf.service_score_avg AS AVG(supplier_perf.service_score)
      COMMENT = 'Average monthly service score.',
    supplier_perf.open_issue_count_total AS SUM(supplier_perf.open_issue_count)
      COMMENT = 'Total open issue count across scorecard months.'
  )

  COMMENT = 'SupplyChainIQ governed Semantic View (Phase 3B). Canonical business-semantic contract over the validated CURATED layer for Cortex Analyst and Cortex Agents. Excludes TRANSPORT_OPTION and INTERPLANT_TRANSFER_OPTION, which remain CURATED decision-support inputs for future Agent Skills. No unsafe independent fact-to-fact relationships are exposed; the intentional Purchase Order Line -> Shipment 1:N business relationship is retained.'

  AI_SQL_GENERATION '
Canonical Supplier OTD (metric shipment.supplier_otd_percent) always compares SHIPMENT.ACTUAL_DELIVERY_DATE to the PARENT PURCHASE ORDER LINE PROMISED_DATE (po_line.promised_date). Never derive OTD directly from EXPECTED_DELIVERY_DATE.
EXPECTED_DELIVERY_DATE on the shipment is only used for Shipment Schedule Adherence (metric shipment.shipment_schedule_adherence_percent), which is a distinct logistics-execution concept, not Supplier OTD.
Fill Rate (metric cust_order_line.fill_rate_percent) always uses SUM(FULFILLED_QTY) divided by SUM(ORDERED_QTY); never average row-level percentages.
Cancelled customer order lines (ORDER_STATUS = CANCELLED) are always excluded from Fill Rate. Cancelled purchase order lines (PO_STATUS = CANCELLED) are always excluded from Supplier OTD and Shipment Schedule Adherence eligibility.
For current or latest inventory position questions, first resolve inv.latest_snapshot_date for the requested Part/Plant, then filter inv.snapshot_date to that value before reading inv.available_qty_metric, inv.on_hand_qty_metric, or inv.safety_stock_qty_metric. Do not assume a single-step latest-value metric exists.
Do not create a direct relationship or join between Inventory Snapshot and Demand, between Shipment and Customer Order Line, or between Supplier Performance and Shipment. These facts are independent and must be queried separately and combined only at the final result level.
Days of Inventory is not a single native metric. Compute it as a two-step calculation: query inv.available_qty_metric (at the latest snapshot date) and demand.avg_daily_demand_30d (at the corresponding date) separately, then divide.
Monetary values (Actual Landed Cost, Purchase Amount, Agreed Unit Price) must never be summed across different currencies. Actual Landed Cost and Purchase Amount must always be grouped by po_line.currency unless the query is already scoped to a single supplier or a single currency. If a user asks for a cross-currency or global monetary total, provide a per-currency breakdown or ask for clarification instead of producing one mixed-currency number.
Actual Landed Cost uses shipment.received_qty, never po_line.order_qty, to avoid duplicating purchase cost when a purchase order line has multiple shipment lines.
Always use the canonical IDs (supplier_id, part_id, plant_id, customer_id, carrier_id) and the relationships defined in this semantic view. Do not construct joins outside the declared relationship graph.
Do not invent a Supplier Risk score. Use supplier_perf.risk_category as the canonical risk signal.
Do not invent a projected or forward-looking Stockout Risk calculation. Use inv.inventory_status as the canonical (point-in-time) stockout signal only.
Inventory Turnover is not supported and must not be approximated with a quantity-based proxy.
Contract Lead Time (supplier_part.contract_lead_time_days_avg), Realized Lead Time (shipment.realized_lead_time_days_avg), and Reported Lead Time (supplier_perf.reported_lead_time_days_avg) are three distinct concepts from three different sources. Never substitute one for another or blend them into a single Lead Time answer.
Do not invent unsupported causal relationships between metrics or entities that are not explicitly connected by a declared relationship.
'

  AI_QUESTION_CATEGORIZATION '
If a question about delivery performance could mean either Supplier OTD (inbound, supplier commitment) or customer-facing fulfillment performance (Fill Rate, due-date adherence), ask the user to clarify which side of the supply chain they mean before generating SQL.
If a question about lead time does not specify which concept is meant, ask whether the user wants Contract Lead Time (the agreed commitment), Realized Lead Time (what actually happened), or Reported Lead Time (the supplier-reported monthly figure).
If a question requests a total or aggregate monetary value (Landed Cost, Purchase Amount) across multiple suppliers or parts without specifying a currency, ask whether the user wants a per-currency breakdown, or confirm they are scoping to a single supplier/currency, before generating SQL.
If a question asks for Inventory Turnover, respond that this metric is not currently supported due to the absence of a costed-inventory or COGS source in this dataset, and offer available alternatives such as Days of Inventory components or Stockout status.
If a question asks for a projected, forward-looking, or predictive Stockout Risk (for example, will we stock out in the next N days), respond that this calculation is deferred to a future Agent Skill and offer the current point-in-time inventory_status instead.
If a question asks about Transport Option or Interplant Transfer Option scenario analysis (for example, expedite shipping options or interplant transfer feasibility), respond that this belongs to future Agent Skills / scenario analysis tools outside this semantic view, since those decision-support tables are intentionally not included here.
'

  AI_VERIFIED_QUERIES (

    VQ01 AS (
      QUESTION 'What is our overall supplier OTD?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_OTD_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS shipment.supplier_otd_percent
)'
    ),

    VQ02 AS (
      QUESTION 'What is the on-time delivery rate for supplier S017?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, SUPPLIER_OTD_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id
  METRICS shipment.supplier_otd_percent
)
WHERE SUPPLIER_ID = ''S017'''
    ),

    VQ03 AS (
      QUESTION 'How is supplier S017 performing on inbound delivery commitments?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, SUPPLIER_OTD_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id
  METRICS shipment.supplier_otd_percent
)
WHERE SUPPLIER_ID = ''S017'''
    ),

    VQ04 AS (
      QUESTION 'What is our shipment schedule adherence?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SHIPMENT_SCHEDULE_ADHERENCE_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS shipment.shipment_schedule_adherence_percent
)'
    ),

    VQ05 AS (
      QUESTION 'What is our overall fill rate?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT FILL_RATE_PERCENT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  METRICS cust_order_line.fill_rate_percent
)'
    ),

    VQ06 AS (
      QUESTION 'What was the available inventory for part P104 at plant P01 on 2026-08-15?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT PART_ID, PLANT_ID, SNAPSHOT_DATE, AVAILABLE_QTY_METRIC
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date
  METRICS inv.available_qty_metric
)
WHERE PART_ID = ''P104'' AND PLANT_ID = ''P01'' AND SNAPSHOT_DATE = ''2026-08-15'''
    ),

    VQ07 AS (
      QUESTION 'What is the 30-day average daily demand for part P104 at plant P01 as of 2026-08-14?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT PART_ID, PLANT_ID, DEMAND_DATE, AVG_DAILY_DEMAND_30D
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, demand.demand_date
  METRICS demand.avg_daily_demand_30d
)
WHERE PART_ID = ''P104'' AND PLANT_ID = ''P01'' AND DEMAND_DATE = ''2026-08-14'''
    ),

    VQ08 AS (
      QUESTION 'What are the contract lead times for suppliers S017 and S042 for P104?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, PART_ID, CONTRACT_LEAD_TIME_DAYS_AVG
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, part.part_id
  METRICS supplier_part.contract_lead_time_days_avg
)
WHERE PART_ID = ''P104'' AND SUPPLIER_ID IN (''S017'', ''S042'')
ORDER BY SUPPLIER_ID'
    ),

    VQ09 AS (
      QUESTION 'What is the current risk category for supplier S017?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, SCORECARD_DATE, RISK_CATEGORY
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, supplier_perf.scorecard_date, supplier_perf.risk_category
)
WHERE SUPPLIER_ID = ''S017''
ORDER BY SCORECARD_DATE DESC
LIMIT 1'
    ),

    VQ10 AS (
      QUESTION 'How many non-cancelled customer order lines for P104 at P01 are due between 2026-08-15 and 2026-08-29, and what is their total order value?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT PART_ID, PLANT_ID, ORDER_LINE_COUNT, TOTAL_ORDER_VALUE
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id
  METRICS COUNT(cust_order_line.order_id) AS ORDER_LINE_COUNT, cust_order_line.total_order_value
  WHERE cust_order_line.order_status <> ''CANCELLED'' AND cust_order_line.due_date BETWEEN ''2026-08-15'' AND ''2026-08-29''
)
WHERE PART_ID = ''P104'' AND PLANT_ID = ''P01'''
    ),

    VQ11 AS (
      QUESTION 'What is the total actual landed cost across all suppliers, broken down by currency?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT CURRENCY, ACTUAL_LANDED_COST
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS po_line.currency
  METRICS shipment.actual_landed_cost
)
ORDER BY CURRENCY'
    ),

    VQ12 AS (
      QUESTION 'What is the actual landed cost for supplier S017, including currency?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, CURRENCY, ACTUAL_LANDED_COST
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, po_line.currency
  METRICS shipment.actual_landed_cost
)
WHERE SUPPLIER_ID = ''S017'''
    ),

    VQ13 AS (
      QUESTION 'Which suppliers are approved to supply P104, and what are their contract lead times and prices?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, PART_ID, CURRENCY, AGREED_UNIT_PRICE, CONTRACT_LEAD_TIME_DAYS_AVG
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id, part.part_id, supplier_part.currency
  METRICS MAX(supplier_part.agreed_unit_price) AS AGREED_UNIT_PRICE, supplier_part.contract_lead_time_days_avg
)
WHERE PART_ID = ''P104''
ORDER BY SUPPLIER_ID'
    ),

    VQ14 AS (
      QUESTION 'Which parts and plants had inventory status BELOW_SAFETY or STOCKOUT on 2026-08-15?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT PART_ID, PLANT_ID, SNAPSHOT_DATE, INVENTORY_STATUS
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS part.part_id, plant.plant_id, inv.snapshot_date, inv.inventory_status
)
WHERE SNAPSHOT_DATE = ''2026-08-15'' AND INVENTORY_STATUS IN (''BELOW_SAFETY'', ''STOCKOUT'')
ORDER BY INVENTORY_STATUS, PART_ID, PLANT_ID'
    ),

    VQ15 AS (
      QUESTION 'Which suppliers have the most overdue purchase order lines?'
      VERIFIED_AT 1787317136
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supplychainiq_team)'
      SQL '
SELECT SUPPLIER_ID, OVERDUE_LINE_COUNT
FROM SEMANTIC_VIEW(
  SUPPLYCHAINIQ_DB.SEMANTIC.SUPPLY_CHAIN_SEMANTIC_VIEW
  DIMENSIONS supplier.supplier_id
  METRICS COUNT(po_line.po_number) AS OVERDUE_LINE_COUNT
  WHERE po_line.po_status = ''OVERDUE''
)
ORDER BY OVERDUE_LINE_COUNT DESC
LIMIT 10'
    )

  )

  COPY GRANTS;
