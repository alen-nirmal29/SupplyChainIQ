/* ============================================================================
   SupplyChainIQ - PHASE 1 : SYNTHETIC DATA FOUNDATION
   FILE    : 02_tables.sql
   PURPOSE : All table definitions.

   DESIGN NOTE - DELIBERATE TERMINOLOGY FRAGMENTATION
   --------------------------------------------------
   The same business concepts carry different column names per source system:

     CONCEPT   SAP_ERP      TMS_LOGISTICS     WMS_INVENTORY  DEMAND_PLANNING  CRM_ORDERS        SUPPLIER_PORTAL
     Supplier  VENDOR_ID    SUPPLIER_CODE     -              -                -                 SUPPLIER_ID
     Part      MATERIAL_NO  ITEM_CODE         SKU            PART_ID          PART_NUMBER       -
     Plant     PLANT_CODE   DESTINATION_SITE  SITE_ID        LOCATION_ID      FULFILLMENT_SITE  -

   Canonical business identifiers (S###, P###, P##, C####, CR##, PO######,
   SH######, CO######, DOC######) stay stable and uncorrupted across systems
   so later harmonization is reliable.

   No primary/foreign keys are enforced (Snowflake does not enforce them);
   referential integrity is guaranteed by generation logic and proven in
   04_data_validation.sql.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SAP_ERP
   =========================================================================== */

CREATE OR REPLACE TABLE SAP_ERP.VENDOR_MASTER (
    VENDOR_ID        VARCHAR(10)  NOT NULL,   -- canonical supplier id  S001..S100
    VENDOR_NAME      VARCHAR(200),
    REGION           VARCHAR(50),             -- hierarchy: Global > REGION > COUNTRY > VENDOR
    COUNTRY          VARCHAR(100),
    COUNTRY_CODE     VARCHAR(5),
    VENDOR_TIER      VARCHAR(30),             -- Strategic / Preferred / Standard / Conditional
    VENDOR_STATUS    VARCHAR(30),             -- Active / Under Review / Inactive
    PAYMENT_TERMS    VARCHAR(20),
    DEFAULT_CURRENCY VARCHAR(5),
    CREATED_DATE     DATE
)
COMMENT = 'ERP supplier master. ERP calls suppliers "vendors" (VENDOR_ID).';

CREATE OR REPLACE TABLE SAP_ERP.MATERIAL_MASTER (
    MATERIAL_NO          VARCHAR(10) NOT NULL, -- canonical part id  P001..P1000
    MATERIAL_DESCRIPTION VARCHAR(300),
    PRODUCT_FAMILY       VARCHAR(60),          -- hierarchy: FAMILY > CATEGORY > PART
    PRODUCT_CATEGORY     VARCHAR(60),
    UNIT_OF_MEASURE      VARCHAR(10),
    STANDARD_COST        NUMBER(14,2),
    WEIGHT               NUMBER(12,3),
    CRITICALITY          VARCHAR(20),          -- Critical / High / Medium / Low
    ACTIVE_FLAG          BOOLEAN
)
COMMENT = 'ERP material master. ERP calls parts "materials" (MATERIAL_NO).';

CREATE OR REPLACE TABLE SAP_ERP.PLANT_MASTER (
    PLANT_CODE   VARCHAR(10) NOT NULL,         -- canonical plant id  P01..P12
    PLANT_NAME   VARCHAR(150),
    REGION       VARCHAR(50),                  -- hierarchy: Global > REGION > COUNTRY > PLANT
    COUNTRY      VARCHAR(100),
    CAPACITY     NUMBER(14,0),
    PLANT_TYPE   VARCHAR(50),
    ACTIVE_FLAG  BOOLEAN
)
COMMENT = 'ERP plant master. ERP calls locations "plants" (PLANT_CODE).';

CREATE OR REPLACE TABLE SAP_ERP.SUPPLIER_MATERIAL (
    VENDOR_ID               VARCHAR(10) NOT NULL,
    MATERIAL_NO             VARCHAR(10) NOT NULL,
    IS_PRIMARY_SUPPLIER     BOOLEAN,
    AGREED_UNIT_PRICE       NUMBER(14,2),
    CONTRACT_LEAD_TIME_DAYS NUMBER(6,0),
    MINIMUM_ORDER_QTY       NUMBER(12,0),
    MAX_WEEKLY_SUPPLY_QTY   NUMBER(12,0),
    CURRENCY                VARCHAR(5),
    VALID_FROM              DATE,
    VALID_TO                DATE
)
COMMENT = 'Many-to-many approved sourcing relationship (which vendor may supply which material, at what price / lead time / capacity).';

CREATE OR REPLACE TABLE SAP_ERP.PURCHASE_ORDER_LINES (
    PO_NUMBER         VARCHAR(20) NOT NULL,    -- PO000001 onward
    PO_LINE_NUMBER    NUMBER(6,0) NOT NULL,
    VENDOR_ID         VARCHAR(10),
    MATERIAL_NO       VARCHAR(10),
    PLANT_CODE        VARCHAR(10),
    ORDER_DATE        DATE,                    -- ERP date terminology
    CONFIRMATION_DATE DATE,                    -- nullable: vendor not always confirmed
    PROMISED_DATE     DATE,                    -- OTD reference date
    ORDER_QTY         NUMBER(14,2),
    UNIT_PRICE        NUMBER(14,2),
    CURRENCY          VARCHAR(5),
    PO_STATUS         VARCHAR(30)              -- OPEN / PARTIALLY_DELIVERED / DELIVERED / CANCELLED / OVERDUE
)
COMMENT = 'ERP purchase order lines at PO_NUMBER + PO_LINE_NUMBER grain. CANCELLED lines must later be excluded from governed OTD.';

/* ===========================================================================
   TMS_LOGISTICS
   =========================================================================== */

CREATE OR REPLACE TABLE TMS_LOGISTICS.CARRIER_MASTER (
    CARRIER_CODE   VARCHAR(10) NOT NULL,       -- CR01 onward
    CARRIER_NAME   VARCHAR(150),
    TRANSPORT_MODE VARCHAR(20),                -- Road / Air / Ocean / Rail
    REGION         VARCHAR(50),
    SERVICE_LEVEL  VARCHAR(20),                -- Standard / Priority / Express
    ACTIVE_FLAG    BOOLEAN
)
COMMENT = 'TMS carrier master.';

CREATE OR REPLACE TABLE TMS_LOGISTICS.SHIPMENTS (
    SHIPMENT_ID             VARCHAR(20) NOT NULL,  -- SH000001 onward
    SHIPMENT_LINE_NUMBER    NUMBER(6,0) NOT NULL,
    PO_REF                  VARCHAR(20),           -- -> SAP_ERP.PURCHASE_ORDER_LINES.PO_NUMBER
    PO_LINE_REF             NUMBER(6,0),           -- -> SAP_ERP.PURCHASE_ORDER_LINES.PO_LINE_NUMBER
    SUPPLIER_CODE           VARCHAR(10),           -- TMS term for VENDOR_ID
    ITEM_CODE               VARCHAR(10),           -- TMS term for MATERIAL_NO
    DESTINATION_SITE        VARCHAR(10),           -- TMS term for PLANT_CODE
    CARRIER_CODE            VARCHAR(10),
    SHIP_DATE               DATE,
    EXPECTED_DELIVERY_DATE  DATE,                  -- carrier commitment
    ACTUAL_DELIVERY_DATE    DATE,                  -- NULL while in transit
    PROJECTED_DELIVERY_DATE DATE,                  -- latest ETA for open shipments
    SHIPPED_QTY             NUMBER(14,2),
    RECEIVED_QTY            NUMBER(14,2),
    FREIGHT_COST            NUMBER(14,2),
    DUTY_COST               NUMBER(14,2),
    HANDLING_COST           NUMBER(14,2),
    OTHER_LOGISTICS_COST    NUMBER(14,2),          -- nullable
    TRANSPORT_MODE          VARCHAR(20),
    SHIPMENT_STATUS         VARCHAR(30)            -- DELIVERED / PARTIAL / IN_TRANSIT / PLANNED
)
COMMENT = 'TMS shipment lines at SHIPMENT_ID + SHIPMENT_LINE_NUMBER grain. Multiple shipments may fulfil one PO line. Landed-cost components live here.';

CREATE OR REPLACE TABLE TMS_LOGISTICS.TRANSPORT_OPTIONS (
    ORIGIN_REGION        VARCHAR(50),
    DESTINATION_PLANT    VARCHAR(10),
    TRANSPORT_MODE       VARCHAR(20),
    NORMAL_TRANSIT_DAYS  NUMBER(6,0),
    EXPEDITED_TRANSIT_DAYS NUMBER(6,0),
    NORMAL_COST_FACTOR   NUMBER(8,3),
    EXPEDITE_COST_FACTOR NUMBER(8,3),
    ACTIVE_FLAG          BOOLEAN
)
COMMENT = 'Lane catalogue supporting later expedite-vs-normal scenario analysis. Facts only - no recommendation logic.';

CREATE OR REPLACE TABLE TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS (
    ORIGIN_PLANT        VARCHAR(10),
    DESTINATION_PLANT   VARCHAR(10),
    TRANSPORT_MODE      VARCHAR(20),
    TRANSIT_DAYS        NUMBER(6,0),
    COST_PER_UNIT       NUMBER(14,2),
    FIXED_TRANSFER_COST NUMBER(14,2),
    MAX_TRANSFER_QTY    NUMBER(12,0),
    ACTIVE_FLAG         BOOLEAN
)
COMMENT = 'Interplant stock-transfer lanes supporting later cross-plant transfer scenario analysis.';

/* ===========================================================================
   WMS_INVENTORY
   =========================================================================== */

CREATE OR REPLACE TABLE WMS_INVENTORY.INVENTORY_SNAPSHOTS (
    SITE_ID          VARCHAR(10) NOT NULL,     -- WMS term for PLANT_CODE
    SKU              VARCHAR(10) NOT NULL,     -- WMS term for MATERIAL_NO
    SNAPSHOT_DATE    DATE        NOT NULL,
    ON_HAND_QTY      NUMBER(14,2),
    RESERVED_QTY     NUMBER(14,2),
    AVAILABLE_QTY    NUMBER(14,2),
    SAFETY_STOCK_QTY NUMBER(14,2),
    IN_TRANSIT_QTY   NUMBER(14,2),
    INVENTORY_STATUS VARCHAR(30)               -- STOCKOUT / BELOW_SAFETY / AT_SAFETY / HEALTHY / EXCESS
)
COMMENT = 'WMS inventory position history at SITE_ID + SKU + SNAPSHOT_DATE grain. Weekly snapshots; latest snapshot date = DATASET_ANCHOR_DATE.';

/* ===========================================================================
   DEMAND_PLANNING
   =========================================================================== */

CREATE OR REPLACE TABLE DEMAND_PLANNING.DEMAND_HISTORY (
    PART_ID           VARCHAR(10) NOT NULL,    -- planning term for MATERIAL_NO
    LOCATION_ID       VARCHAR(10) NOT NULL,    -- planning term for PLANT_CODE
    DEMAND_DATE       DATE        NOT NULL,
    FORECAST_QTY      NUMBER(14,2),
    ACTUAL_DEMAND_QTY NUMBER(14,2),
    FORECAST_VERSION  VARCHAR(30),
    DEMAND_SOURCE     VARCHAR(50),
    DEMAND_PATTERN    VARCHAR(30)              -- descriptive attribute (Stable/Seasonal/Volatile/...)
)
COMMENT = 'Daily demand history and forecast at PART_ID + LOCATION_ID + DEMAND_DATE grain. Supports later governed average-daily-demand and DOI.';

/* ===========================================================================
   CRM_ORDERS
   =========================================================================== */

CREATE OR REPLACE TABLE CRM_ORDERS.CUSTOMER_MASTER (
    CUSTOMER_ID      VARCHAR(10) NOT NULL,     -- C0001 onward
    CUSTOMER_NAME    VARCHAR(200),
    CUSTOMER_SEGMENT VARCHAR(30),              -- Strategic / Enterprise / Mid-Market / Standard
    REGION           VARCHAR(50),
    COUNTRY          VARCHAR(100),
    PRIORITY_TIER    VARCHAR(10),              -- P1 / P2 / P3 / P4
    ACTIVE_FLAG      BOOLEAN
)
COMMENT = 'CRM business-customer master. Synthetic company-style names only - no person-level PII.';

CREATE OR REPLACE TABLE CRM_ORDERS.CUSTOMER_ORDER_LINES (
    ORDER_ID        VARCHAR(20) NOT NULL,      -- CO000001 onward
    ORDER_LINE      NUMBER(6,0) NOT NULL,
    CUSTOMER_ID     VARCHAR(10),
    PART_NUMBER     VARCHAR(10),               -- CRM term for MATERIAL_NO
    FULFILLMENT_SITE VARCHAR(10),              -- CRM term for PLANT_CODE
    ORDER_DATE      DATE,
    REQUESTED_DATE  DATE,                      -- CRM date terminology
    DUE_DATE        DATE,
    ORDERED_QTY     NUMBER(14,2),
    FULFILLED_QTY   NUMBER(14,2),
    UNIT_SELL_PRICE NUMBER(14,2),
    ORDER_VALUE     NUMBER(18,2),              -- ORDERED_QTY * UNIT_SELL_PRICE, in INR
    ORDER_STATUS    VARCHAR(30),               -- OPEN / PARTIALLY_FULFILLED / FULFILLED / CANCELLED / OVERDUE
    PRIORITY        VARCHAR(20)                -- CRITICAL / HIGH / MEDIUM / LOW
)
COMMENT = 'CRM customer order lines. Raw fulfilled/ordered quantities only - the canonical Fill Rate metric is NOT precomputed here.';

/* ===========================================================================
   SUPPLIER_PORTAL
   =========================================================================== */

CREATE OR REPLACE TABLE SUPPLIER_PORTAL.SUPPLIER_SCORECARDS (
    SUPPLIER_ID             VARCHAR(10) NOT NULL,   -- portal term for VENDOR_ID
    SCORECARD_DATE          DATE        NOT NULL,
    QUALITY_SCORE           NUMBER(6,2),
    REJECTION_RATE          NUMBER(8,4),            -- fraction, e.g. 0.0250 = 2.5%
    REPORTED_LEAD_TIME_DAYS NUMBER(8,2),
    LEAD_TIME_VARIABILITY   NUMBER(8,2),            -- std deviation in days
    SERVICE_SCORE           NUMBER(6,2),
    RISK_CATEGORY           VARCHAR(20),            -- Low / Medium / High / Critical
    OPEN_ISSUE_COUNT        NUMBER(8,0)
)
COMMENT = 'Monthly supplier scorecard history from the supplier portal. Multidimensional: delivery, quality and service risk are independent.';

CREATE OR REPLACE TABLE SUPPLIER_PORTAL.SUPPLIER_PROFILE (
    SUPPLIER_ID          VARCHAR(10) NOT NULL,
    SUPPLIER_NAME        VARCHAR(200),               -- deliberately different FORMATTING from ERP VENDOR_NAME
    SUPPLIER_COUNTRY     VARCHAR(100),
    PORTAL_STATUS        VARCHAR(30),
    ONBOARDED_ON         DATE,
    PRIMARY_CONTACT_ROLE VARCHAR(80)                 -- role only, never a person name
)
COMMENT = 'Portal-side supplier profile. Demonstrates controlled display-name formatting drift vs ERP VENDOR_NAME while SUPPLIER_ID stays canonical.';

/* ===========================================================================
   DOCUMENTS
   =========================================================================== */

CREATE OR REPLACE TABLE DOCUMENTS.SUPPLIER_DOCUMENTS (
    DOCUMENT_ID      VARCHAR(20) NOT NULL,     -- DOC000001 onward
    SUPPLIER_ID      VARCHAR(10),              -- NULL for company-wide policies
    DOCUMENT_TYPE    VARCHAR(60),              -- Supplier Contract / SLA / Procurement Policy / Supplier Scorecard Narrative / Logistics Policy / Quality Agreement
    TITLE            VARCHAR(300),
    EFFECTIVE_DATE   DATE,
    EXPIRY_DATE      DATE,
    CONTENT          VARCHAR(16777216),        -- multi-paragraph synthetic business text
    SOURCE_REFERENCE VARCHAR(200),
    CREATED_AT       TIMESTAMP_LTZ
)
COMMENT = 'Synthetic supplier/procurement documents for later Cortex Search indexing. Generated from deterministic SQL templates - no per-document LLM calls.';

SELECT 'Phase 1 / 02_tables.sql complete' AS STATUS;
