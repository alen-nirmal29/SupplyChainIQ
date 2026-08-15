/* ============================================================================
   SupplyChainIQ - Governed Agentic Supply Chain Control Tower
   PHASE 1 : SYNTHETIC DATA FOUNDATION
   FILE    : 01_database.sql
   PURPOSE : Database, source-system schemas, environment config,
             dataset anchor-date initialization.

   SAFETY  : This script only creates / touches objects inside
             SUPPLYCHAINIQ_DB. Nothing outside that database is modified.
             It is safely rerunnable (IF NOT EXISTS / CREATE OR REPLACE on
             the metadata table only).

   NOTE ON THE ANCHOR DATE
   -----------------------
   DATASET_ANCHOR_DATE is a FIXED project constant (DATE '2026-08-15') for
   dataset VERSION 1. It is deliberately NOT CURRENT_DATE() so that the
   dataset - including every historical, future and flagship-scenario date -
   is byte-for-byte reproducible on any rebuild, in any session timezone.
   Every downstream script reads the anchor from PUBLIC.DATASET_METADATA.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;          -- smallest existing warehouse (X-Small)

/* ---------------------------------------------------------------------------
   1. DATABASE
   --------------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS SUPPLYCHAINIQ_DB
  COMMENT = 'SupplyChainIQ - synthetic multi-source-system supply chain data foundation (hackathon). Phase 1 = raw source data only.';

USE DATABASE SUPPLYCHAINIQ_DB;

/* ---------------------------------------------------------------------------
   2. SOURCE-SYSTEM SCHEMAS
      Each schema simulates a different operational system with its own
      terminology. They are intentionally NOT harmonized at this phase.
   --------------------------------------------------------------------------- */
CREATE SCHEMA IF NOT EXISTS SAP_ERP
  COMMENT = 'Simulated SAP ERP: supplier (vendor) master, material master, plant master, sourcing, purchase orders. Terminology: VENDOR_ID / MATERIAL_NO / PLANT_CODE.';

CREATE SCHEMA IF NOT EXISTS TMS_LOGISTICS
  COMMENT = 'Simulated Transport Management System: carriers, shipments, transport options, interplant transfer lanes. Terminology: SUPPLIER_CODE / ITEM_CODE / DESTINATION_SITE.';

CREATE SCHEMA IF NOT EXISTS WMS_INVENTORY
  COMMENT = 'Simulated Warehouse Management System: inventory snapshots and history. Terminology: SKU / SITE_ID.';

CREATE SCHEMA IF NOT EXISTS DEMAND_PLANNING
  COMMENT = 'Simulated demand planning / forecasting system. Terminology: PART_ID / LOCATION_ID.';

CREATE SCHEMA IF NOT EXISTS CRM_ORDERS
  COMMENT = 'Simulated CRM / order management: customer master and customer order lines. Terminology: PART_NUMBER / FULFILLMENT_SITE.';

CREATE SCHEMA IF NOT EXISTS SUPPLIER_PORTAL
  COMMENT = 'Simulated supplier collaboration portal: supplier scorecards and operational supplier profile. Terminology: SUPPLIER_ID.';

CREATE SCHEMA IF NOT EXISTS DOCUMENTS
  COMMENT = 'Synthetic unstructured supplier documents (contracts, SLAs, policies, narratives) intended for later Cortex Search indexing.';

CREATE SCHEMA IF NOT EXISTS CURATED
  COMMENT = 'RESERVED for the future canonical ontology-aligned model. Intentionally EMPTY in Phase 1.';

/* ---------------------------------------------------------------------------
   3. DATASET METADATA / ANCHOR DATE
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE PUBLIC.DATASET_METADATA (
    DATASET_NAME        VARCHAR(100) NOT NULL,
    DATASET_ANCHOR_DATE DATE         NOT NULL,
    GENERATED_AT        TIMESTAMP_LTZ NOT NULL,
    VERSION             NUMBER(6,0)  NOT NULL,
    NOTES               VARCHAR(1000)
)
COMMENT = 'Single source of truth for the dataset anchor date. All relative dates in 03_seed_data.sql and 04_data_validation.sql derive from DATASET_ANCHOR_DATE. Never call CURRENT_DATE() in generation or validation.';

INSERT INTO PUBLIC.DATASET_METADATA
  (DATASET_NAME, DATASET_ANCHOR_DATE, GENERATED_AT, VERSION, NOTES)
SELECT
  'SUPPLYCHAINIQ_SYNTHETIC_FOUNDATION',
  DATE '2026-08-15',
  CURRENT_TIMESTAMP(),
  1,
  'Fixed anchor date for reproducibility. Monetary values: purchase/logistics costs in the vendor default currency; CRM customer order values are in INR. Flagship scenario = supplier S017 / part P104 / plant P01.';

/* ---------------------------------------------------------------------------
   4. GENERATION HELPER (infrastructure, not business data)
      Shared driver of ACTIVE Part x Plant combinations. Used by BOTH
      WMS_INVENTORY.INVENTORY_SNAPSHOTS and DEMAND_PLANNING.DEMAND_HISTORY so
      that inventory positions have matching demand history (required for
      future Days-of-Inventory and stockout-risk analysis).
      Populated in 03_seed_data.sql.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE PUBLIC.PART_SITE_COVERAGE (
    PART_SEQ              NUMBER(10,0),
    MATERIAL_NO           VARCHAR(10),
    PLANT_CODE            VARCHAR(10),
    IS_PRIMARY_SITE       BOOLEAN,
    BASE_DAILY_DEMAND     NUMBER(12,2),
    DEMAND_PATTERN        VARCHAR(30),
    INVENTORY_PATTERN     VARCHAR(30),
    SAFETY_STOCK_DAYS     NUMBER(5,1)
)
COMMENT = 'Generation-infrastructure driver table (not a business entity): the active Part x Plant network shared by inventory and demand generation.';

SELECT 'Phase 1 / 01_database.sql complete' AS STATUS,
       DATASET_ANCHOR_DATE,
       VERSION
FROM PUBLIC.DATASET_METADATA
WHERE VERSION = 1;
