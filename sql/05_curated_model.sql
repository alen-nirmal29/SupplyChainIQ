/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 2B : CANONICAL CURATED MODEL
   FILE    : 05_curated_model.sql
   PURPOSE : Create the canonical, ontology-aligned CURATED business layer as
             read-only VIEWS over the Phase 1 source-system tables.

   SAFETY  : This script ONLY creates views inside SUPPLYCHAINIQ_DB.CURATED.
             It performs no DROP / TRUNCATE / DELETE / UPDATE / INSERT against
             any Phase 1 source object, and reads from source tables only via
             SELECT. It is safely rerunnable (CREATE OR REPLACE VIEW).

   SCOPE   : Exactly 14 canonical views, each 1:1 (or 1:1 LEFT JOIN, in the
             case of SUPPLIER) with its Phase 1 source table(s). No physical
             data duplication. See docs/ontology.md for full entity design.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;
USE SCHEMA CURATED;

/* ---------------------------------------------------------------------------
   1. SUPPLIER
      Base: SAP_ERP.VENDOR_MASTER (system of record for identity/name)
      LEFT JOIN SUPPLIER_PORTAL.SUPPLIER_PROFILE on canonical SUPPLIER_ID.
      Monthly SUPPLIER_SCORECARDS are NEVER joined here (see SUPPLIER_PERFORMANCE).
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.SUPPLIER
COMMENT = 'Canonical Supplier: one row per SUPPLIER_ID. ERP VENDOR_MASTER is system of record for identity/name; SUPPLIER_PROFILE portal attributes are enriched via LEFT JOIN. SUPPLIER_NAME_PORTAL preserves the portal''s differently-formatted name for lineage. Monthly scorecards are NOT joined here - see CURATED.SUPPLIER_PERFORMANCE.'
AS
SELECT
    v.VENDOR_ID                    AS SUPPLIER_ID,
    v.VENDOR_NAME                  AS SUPPLIER_NAME,
    p.SUPPLIER_NAME                AS SUPPLIER_NAME_PORTAL,
    v.REGION                       AS REGION,
    v.COUNTRY                      AS COUNTRY,
    v.COUNTRY_CODE                 AS COUNTRY_CODE,
    v.VENDOR_TIER                  AS VENDOR_TIER,
    v.VENDOR_STATUS                AS VENDOR_STATUS,
    v.PAYMENT_TERMS                AS PAYMENT_TERMS,
    v.DEFAULT_CURRENCY             AS DEFAULT_CURRENCY,
    v.CREATED_DATE                 AS CREATED_DATE,
    p.SUPPLIER_COUNTRY             AS SUPPLIER_COUNTRY_PORTAL,
    p.PORTAL_STATUS                AS PORTAL_STATUS,
    p.ONBOARDED_ON                 AS ONBOARDED_ON,
    p.PRIMARY_CONTACT_ROLE         AS PRIMARY_CONTACT_ROLE,
    IFF(p.SUPPLIER_ID IS NOT NULL, TRUE, FALSE) AS HAS_PORTAL_PROFILE
FROM SAP_ERP.VENDOR_MASTER v
LEFT JOIN SUPPLIER_PORTAL.SUPPLIER_PROFILE p
    ON p.SUPPLIER_ID = v.VENDOR_ID;

/* ---------------------------------------------------------------------------
   2. PART
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.PART
COMMENT = 'Canonical Part: one row per PART_ID, sourced 1:1 from SAP_ERP.MATERIAL_MASTER.'
AS
SELECT
    m.MATERIAL_NO                  AS PART_ID,
    m.MATERIAL_DESCRIPTION         AS PART_DESCRIPTION,
    m.PRODUCT_FAMILY                AS PRODUCT_FAMILY,
    m.PRODUCT_CATEGORY              AS PRODUCT_CATEGORY,
    m.UNIT_OF_MEASURE               AS UNIT_OF_MEASURE,
    m.STANDARD_COST                 AS STANDARD_COST,
    m.WEIGHT                        AS WEIGHT,
    m.CRITICALITY                   AS CRITICALITY,
    m.ACTIVE_FLAG                   AS ACTIVE_FLAG
FROM SAP_ERP.MATERIAL_MASTER m;

/* ---------------------------------------------------------------------------
   3. PLANT
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.PLANT
COMMENT = 'Canonical Plant: one row per PLANT_ID, sourced 1:1 from SAP_ERP.PLANT_MASTER.'
AS
SELECT
    pl.PLANT_CODE                   AS PLANT_ID,
    pl.PLANT_NAME                   AS PLANT_NAME,
    pl.REGION                       AS REGION,
    pl.COUNTRY                      AS COUNTRY,
    pl.CAPACITY                     AS CAPACITY,
    pl.PLANT_TYPE                   AS PLANT_TYPE,
    pl.ACTIVE_FLAG                  AS ACTIVE_FLAG
FROM SAP_ERP.PLANT_MASTER pl;

/* ---------------------------------------------------------------------------
   4. SUPPLIER_PART  (bridge: approved sourcing agreement, Supplier N <-> N Part)
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.SUPPLIER_PART
COMMENT = 'Canonical Supplier-Part bridge: one row per approved SUPPLIER_ID x PART_ID sourcing agreement, sourced 1:1 from SAP_ERP.SUPPLIER_MATERIAL. CURRENCY preserved unconverted per agreement.'
AS
SELECT
    sm.VENDOR_ID                    AS SUPPLIER_ID,
    sm.MATERIAL_NO                  AS PART_ID,
    sm.IS_PRIMARY_SUPPLIER          AS IS_PRIMARY_SUPPLIER,
    sm.AGREED_UNIT_PRICE            AS AGREED_UNIT_PRICE,
    sm.CONTRACT_LEAD_TIME_DAYS      AS CONTRACT_LEAD_TIME_DAYS,
    sm.MINIMUM_ORDER_QTY            AS MINIMUM_ORDER_QTY,
    sm.MAX_WEEKLY_SUPPLY_QTY        AS MAX_WEEKLY_SUPPLY_QTY,
    sm.CURRENCY                     AS CURRENCY,
    sm.VALID_FROM                   AS VALID_FROM,
    sm.VALID_TO                     AS VALID_TO
FROM SAP_ERP.SUPPLIER_MATERIAL sm;

/* ---------------------------------------------------------------------------
   5. PURCHASE_ORDER_LINE
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.PURCHASE_ORDER_LINE
COMMENT = 'Canonical Purchase Order Line: one row per (PO_NUMBER, PO_LINE_NUMBER), sourced 1:1 from SAP_ERP.PURCHASE_ORDER_LINES. CANCELLED lines are retained (not filtered); CURRENCY preserved unconverted.'
AS
SELECT
    pol.PO_NUMBER                   AS PO_NUMBER,
    pol.PO_LINE_NUMBER              AS PO_LINE_NUMBER,
    pol.VENDOR_ID                   AS SUPPLIER_ID,
    pol.MATERIAL_NO                 AS PART_ID,
    pol.PLANT_CODE                  AS PLANT_ID,
    pol.ORDER_DATE                  AS ORDER_DATE,
    pol.CONFIRMATION_DATE           AS CONFIRMATION_DATE,
    pol.PROMISED_DATE               AS PROMISED_DATE,
    pol.ORDER_QTY                   AS ORDER_QTY,
    pol.UNIT_PRICE                  AS UNIT_PRICE,
    pol.CURRENCY                    AS CURRENCY,
    pol.PO_STATUS                   AS PO_STATUS
FROM SAP_ERP.PURCHASE_ORDER_LINES pol;

/* ---------------------------------------------------------------------------
   6. SHIPMENT
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.SHIPMENT
COMMENT = 'Canonical Shipment: one row per (SHIPMENT_ID, SHIPMENT_LINE_NUMBER), sourced 1:1 from TMS_LOGISTICS.SHIPMENTS. Landed-cost components (FREIGHT/DUTY/HANDLING/OTHER_LOGISTICS_COST) are in the referenced PO''s currency - no local currency column exists on this source table.'
AS
SELECT
    s.SHIPMENT_ID                   AS SHIPMENT_ID,
    s.SHIPMENT_LINE_NUMBER          AS SHIPMENT_LINE_NUMBER,
    s.PO_REF                        AS PO_NUMBER,
    s.PO_LINE_REF                   AS PO_LINE_NUMBER,
    s.SUPPLIER_CODE                 AS SUPPLIER_ID,
    s.ITEM_CODE                     AS PART_ID,
    s.DESTINATION_SITE               AS PLANT_ID,
    s.CARRIER_CODE                  AS CARRIER_ID,
    s.SHIP_DATE                     AS SHIP_DATE,
    s.EXPECTED_DELIVERY_DATE        AS EXPECTED_DELIVERY_DATE,
    s.ACTUAL_DELIVERY_DATE          AS ACTUAL_DELIVERY_DATE,
    s.PROJECTED_DELIVERY_DATE       AS PROJECTED_DELIVERY_DATE,
    s.SHIPPED_QTY                   AS SHIPPED_QTY,
    s.RECEIVED_QTY                  AS RECEIVED_QTY,
    s.FREIGHT_COST                  AS FREIGHT_COST,
    s.DUTY_COST                     AS DUTY_COST,
    s.HANDLING_COST                 AS HANDLING_COST,
    s.OTHER_LOGISTICS_COST          AS OTHER_LOGISTICS_COST,
    s.TRANSPORT_MODE                AS TRANSPORT_MODE,
    s.SHIPMENT_STATUS               AS SHIPMENT_STATUS
FROM TMS_LOGISTICS.SHIPMENTS s;

/* ---------------------------------------------------------------------------
   7. INVENTORY_SNAPSHOT
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.INVENTORY_SNAPSHOT
COMMENT = 'Canonical Inventory Snapshot: one row per (PART_ID, PLANT_ID, SNAPSHOT_DATE), sourced 1:1 from WMS_INVENTORY.INVENTORY_SNAPSHOTS.'
AS
SELECT
    inv.SKU                         AS PART_ID,
    inv.SITE_ID                     AS PLANT_ID,
    inv.SNAPSHOT_DATE               AS SNAPSHOT_DATE,
    inv.ON_HAND_QTY                 AS ON_HAND_QTY,
    inv.RESERVED_QTY                AS RESERVED_QTY,
    inv.AVAILABLE_QTY               AS AVAILABLE_QTY,
    inv.SAFETY_STOCK_QTY            AS SAFETY_STOCK_QTY,
    inv.IN_TRANSIT_QTY              AS IN_TRANSIT_QTY,
    inv.INVENTORY_STATUS            AS INVENTORY_STATUS
FROM WMS_INVENTORY.INVENTORY_SNAPSHOTS inv;

/* ---------------------------------------------------------------------------
   8. DEMAND
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.DEMAND
COMMENT = 'Canonical Demand: one row per (PART_ID, PLANT_ID, DEMAND_DATE), sourced 1:1 from DEMAND_PLANNING.DEMAND_HISTORY.'
AS
SELECT
    d.PART_ID                       AS PART_ID,
    d.LOCATION_ID                   AS PLANT_ID,
    d.DEMAND_DATE                   AS DEMAND_DATE,
    d.FORECAST_QTY                  AS FORECAST_QTY,
    d.ACTUAL_DEMAND_QTY             AS ACTUAL_DEMAND_QTY,
    d.FORECAST_VERSION              AS FORECAST_VERSION,
    d.DEMAND_SOURCE                 AS DEMAND_SOURCE,
    d.DEMAND_PATTERN                AS DEMAND_PATTERN
FROM DEMAND_PLANNING.DEMAND_HISTORY d;

/* ---------------------------------------------------------------------------
   9. CUSTOMER
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.CUSTOMER
COMMENT = 'Canonical Customer: one row per CUSTOMER_ID, sourced 1:1 from CRM_ORDERS.CUSTOMER_MASTER.'
AS
SELECT
    c.CUSTOMER_ID                   AS CUSTOMER_ID,
    c.CUSTOMER_NAME                 AS CUSTOMER_NAME,
    c.CUSTOMER_SEGMENT               AS CUSTOMER_SEGMENT,
    c.REGION                        AS REGION,
    c.COUNTRY                       AS COUNTRY,
    c.PRIORITY_TIER                  AS PRIORITY_TIER,
    c.ACTIVE_FLAG                   AS ACTIVE_FLAG
FROM CRM_ORDERS.CUSTOMER_MASTER c;

/* ---------------------------------------------------------------------------
   10. CUSTOMER_ORDER_LINE
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.CUSTOMER_ORDER_LINE
COMMENT = 'Canonical Customer Order Line: one row per (ORDER_ID, ORDER_LINE), sourced 1:1 from CRM_ORDERS.CUSTOMER_ORDER_LINES. ORDER_VALUE is denominated in INR - do not mix with PO/shipment costs (vendor default currency) when aggregating.'
AS
SELECT
    col.ORDER_ID                    AS ORDER_ID,
    col.ORDER_LINE                  AS ORDER_LINE,
    col.CUSTOMER_ID                 AS CUSTOMER_ID,
    col.PART_NUMBER                 AS PART_ID,
    col.FULFILLMENT_SITE            AS PLANT_ID,
    col.ORDER_DATE                  AS ORDER_DATE,
    col.REQUESTED_DATE              AS REQUESTED_DATE,
    col.DUE_DATE                    AS DUE_DATE,
    col.ORDERED_QTY                 AS ORDERED_QTY,
    col.FULFILLED_QTY               AS FULFILLED_QTY,
    col.UNIT_SELL_PRICE             AS UNIT_SELL_PRICE,
    col.ORDER_VALUE                 AS ORDER_VALUE,
    col.ORDER_STATUS                AS ORDER_STATUS,
    col.PRIORITY                    AS PRIORITY
FROM CRM_ORDERS.CUSTOMER_ORDER_LINES col;

/* ---------------------------------------------------------------------------
   11. CARRIER
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.CARRIER
COMMENT = 'Canonical Carrier: one row per CARRIER_ID, sourced 1:1 from TMS_LOGISTICS.CARRIER_MASTER.'
AS
SELECT
    cm.CARRIER_CODE                 AS CARRIER_ID,
    cm.CARRIER_NAME                 AS CARRIER_NAME,
    cm.TRANSPORT_MODE                AS TRANSPORT_MODE,
    cm.REGION                       AS REGION,
    cm.SERVICE_LEVEL                 AS SERVICE_LEVEL,
    cm.ACTIVE_FLAG                  AS ACTIVE_FLAG
FROM TMS_LOGISTICS.CARRIER_MASTER cm;

/* ---------------------------------------------------------------------------
   12. SUPPLIER_PERFORMANCE
       Kept as a SEPARATE time-grained fact (Supplier x Scorecard Month).
       NEVER flattened into CURATED.SUPPLIER.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.SUPPLIER_PERFORMANCE
COMMENT = 'Canonical Supplier Performance: one row per (SUPPLIER_ID, SCORECARD_DATE), sourced 1:1 from SUPPLIER_PORTAL.SUPPLIER_SCORECARDS. Deliberately kept separate from CURATED.SUPPLIER (one-row-per-supplier) - never flatten/aggregate into it.'
AS
SELECT
    sc.SUPPLIER_ID                  AS SUPPLIER_ID,
    sc.SCORECARD_DATE               AS SCORECARD_DATE,
    sc.QUALITY_SCORE                AS QUALITY_SCORE,
    sc.REJECTION_RATE                AS REJECTION_RATE,
    sc.REPORTED_LEAD_TIME_DAYS      AS REPORTED_LEAD_TIME_DAYS,
    sc.LEAD_TIME_VARIABILITY        AS LEAD_TIME_VARIABILITY,
    sc.SERVICE_SCORE                 AS SERVICE_SCORE,
    sc.RISK_CATEGORY                AS RISK_CATEGORY,
    sc.OPEN_ISSUE_COUNT              AS OPEN_ISSUE_COUNT
FROM SUPPLIER_PORTAL.SUPPLIER_SCORECARDS sc;

/* ---------------------------------------------------------------------------
   13. TRANSPORT_OPTION
       Origin remains REGION (not Plant) - real structural asymmetry vs.
       Interplant Transfer Option, preserved as-is.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.TRANSPORT_OPTION
COMMENT = 'Canonical Transport Option: one row per (ORIGIN_REGION, DESTINATION_PLANT_ID, TRANSPORT_MODE) lane, sourced 1:1 from TMS_LOGISTICS.TRANSPORT_OPTIONS. Origin is a REGION, not a Plant - preserved as-is, not forced into plant-to-plant shape.'
AS
SELECT
    t.ORIGIN_REGION                 AS ORIGIN_REGION,
    t.DESTINATION_PLANT             AS DESTINATION_PLANT_ID,
    t.TRANSPORT_MODE                AS TRANSPORT_MODE,
    t.NORMAL_TRANSIT_DAYS           AS NORMAL_TRANSIT_DAYS,
    t.EXPEDITED_TRANSIT_DAYS        AS EXPEDITED_TRANSIT_DAYS,
    t.NORMAL_COST_FACTOR            AS NORMAL_COST_FACTOR,
    t.EXPEDITE_COST_FACTOR          AS EXPEDITE_COST_FACTOR,
    t.ACTIVE_FLAG                   AS ACTIVE_FLAG
FROM TMS_LOGISTICS.TRANSPORT_OPTIONS t;

/* ---------------------------------------------------------------------------
   14. INTERPLANT_TRANSFER_OPTION
       Strictly Plant -> Plant (unlike Transport Option).
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW CURATED.INTERPLANT_TRANSFER_OPTION
COMMENT = 'Canonical Interplant Transfer Option: one row per (ORIGIN_PLANT_ID, DESTINATION_PLANT_ID, TRANSPORT_MODE) lane, sourced 1:1 from TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS. Strictly Plant -> Plant.'
AS
SELECT
    it.ORIGIN_PLANT                 AS ORIGIN_PLANT_ID,
    it.DESTINATION_PLANT            AS DESTINATION_PLANT_ID,
    it.TRANSPORT_MODE               AS TRANSPORT_MODE,
    it.TRANSIT_DAYS                 AS TRANSIT_DAYS,
    it.COST_PER_UNIT                AS COST_PER_UNIT,
    it.FIXED_TRANSFER_COST          AS FIXED_TRANSFER_COST,
    it.MAX_TRANSFER_QTY             AS MAX_TRANSFER_QTY,
    it.ACTIVE_FLAG                  AS ACTIVE_FLAG
FROM TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS it;

SELECT 'Phase 2B / 05_curated_model.sql complete - 14 CURATED views created' AS STATUS;
