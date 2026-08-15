/* ============================================================================
   SupplyChainIQ - PHASE 1 : SYNTHETIC DATA FOUNDATION
   FILE    : 03_seed_data.sql
   PURPOSE : Deterministic synthetic data generation, normal business
             distributions, deliberate edge cases, flagship demo scenario.

   DETERMINISM
   -----------
   * No RANDOM(). Pseudo-random variation uses ABS(HASH(<stable ids>,'salt'))
     which is deterministic in Snowflake, so rebuilds are identical.
   * No CURRENT_DATE(). Every date derives from PUBLIC.DATASET_METADATA
     .DATASET_ANCHOR_DATE (fixed at 2026-08-15 for VERSION 1).
   * Set-based generation with GENERATOR / FLATTEN only - no row-by-row
     INSERTs, no LLM calls, no external APIs.
   * Every section TRUNCATEs before INSERT, so the script is rerunnable.

   FLAGSHIP SCENARIO (supplier S017 / part P104 / plant P01)
   --------------------------------------------------------
   Nothing about the flagship answer is stored as a precomputed result.
   The 2,150-unit shortage is derivable only from inventory + safety stock +
   customer order demand + delayed inbound supply timing.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SUPPLYCHAINIQ_DB;

/* ===========================================================================
   SECTION 1 : SAP_ERP.PLANT_MASTER  (12 plants)
   P01 = flagship destination plant, P03 = interplant transfer source.
   P01/P02/P03 are all in India so a 2-3 day road transfer lane is credible.
   =========================================================================== */
TRUNCATE TABLE SAP_ERP.PLANT_MASTER;
INSERT INTO SAP_ERP.PLANT_MASTER
  (PLANT_CODE, PLANT_NAME, REGION, COUNTRY, CAPACITY, PLANT_TYPE, ACTIVE_FLAG)
VALUES
  ('P01','Pune Assembly Plant',            'APAC','India',        250000,'Final Assembly', TRUE),
  ('P02','Bengaluru Electronics Plant',    'APAC','India',        180000,'Electronics',    TRUE),
  ('P03','Chennai Components Plant',       'APAC','India',        210000,'Components',     TRUE),
  ('P04','Shanghai Manufacturing Plant',   'APAC','China',        320000,'Manufacturing',  TRUE),
  ('P05','Ho Chi Minh Assembly Plant',     'APAC','Vietnam',      140000,'Final Assembly', TRUE),
  ('P06','Stuttgart Precision Plant',      'EMEA','Germany',      190000,'Precision',      TRUE),
  ('P07','Wroclaw Assembly Plant',         'EMEA','Poland',       160000,'Final Assembly', TRUE),
  ('P08','Izmir Components Plant',         'EMEA','Turkey',       120000,'Components',     TRUE),
  ('P09','Detroit Assembly Plant',         'AMER','United States',230000,'Final Assembly', TRUE),
  ('P10','Monterrey Manufacturing Plant',  'AMER','Mexico',       175000,'Manufacturing',  TRUE),
  ('P11','Sao Paulo Components Plant',     'AMER','Brazil',       110000,'Components',     TRUE),
  ('P12','Osaka Precision Plant',          'APAC','Japan',        150000,'Precision',      TRUE);

/* ===========================================================================
   SECTION 2 : SAP_ERP.VENDOR_MASTER  (100 suppliers, S001..S100)
   S017 -> China / APAC, Standard tier, Active : becomes the high-risk supplier
   S042 -> India / APAC, Preferred tier, Active: becomes the strong alternate
           (India origin keeps a 7-day alternate lead time to P01 credible)
   =========================================================================== */
TRUNCATE TABLE SAP_ERP.VENDOR_MASTER;
INSERT INTO SAP_ERP.VENDOR_MASTER
  (VENDOR_ID, VENDOR_NAME, REGION, COUNTRY, COUNTRY_CODE, VENDOR_TIER,
   VENDOR_STATUS, PAYMENT_TERMS, DEFAULT_CURRENCY, CREATED_DATE)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
  FROM TABLE(GENERATOR(ROWCOUNT => 100))
),
calc AS (
  SELECT
    n,
    MOD(n * 17, 250)                                             AS nidx,
    CASE WHEN n = 17 THEN 1 WHEN n = 42 THEN 0
         ELSE MOD(n * 5, 12) END                                 AS gi
  FROM s
)
SELECT
  'S' || LPAD(c.n::VARCHAR, 3, '0')                              AS VENDOR_ID,
  GET(ARRAY_CONSTRUCT('Apex','Northwind','Vertex','Ironclad','Bluepeak','Cascade',
                      'Summit','Orion','Meridian','Kestrel','Granite','Lumen',
                      'Sterling','Everest','Pinnacle','Harbour','Redwood','Zenith',
                      'Anchor','Falcon','Copperline','Silverbrook','Trident',
                      'Wavelength','Quarrystone'), MOD(c.nidx, 25))::VARCHAR
  || ' ' ||
  GET(ARRAY_CONSTRUCT('Components Ltd','Industries','Manufacturing','Precision Works',
                      'Technologies','Metalworks','Polymers','Electronics','Fasteners',
                      'Engineering'), FLOOR(c.nidx / 25))::VARCHAR                AS VENDOR_NAME,
  GET(ARRAY_CONSTRUCT('APAC','APAC','APAC','APAC','EMEA','EMEA','EMEA','EMEA',
                      'AMER','AMER','AMER','APAC'), c.gi)::VARCHAR               AS REGION,
  GET(ARRAY_CONSTRUCT('India','China','Vietnam','Japan','Germany','Poland','Italy',
                      'Turkey','United States','Mexico','Brazil','South Korea'), c.gi)::VARCHAR AS COUNTRY,
  GET(ARRAY_CONSTRUCT('IN','CN','VN','JP','DE','PL','IT','TR','US','MX','BR','KR'), c.gi)::VARCHAR AS COUNTRY_CODE,
  CASE WHEN c.n = 17 THEN 'Standard'
       WHEN c.n = 42 THEN 'Preferred'
       WHEN MOD(c.n, 10) IN (0, 1)       THEN 'Strategic'
       WHEN MOD(c.n, 10) IN (2, 3, 4, 5) THEN 'Preferred'
       WHEN MOD(c.n, 10) IN (6, 7, 8)    THEN 'Standard'
       ELSE 'Conditional' END                                                    AS VENDOR_TIER,
  CASE WHEN c.n IN (11, 17, 42, 55, 64, 73, 88) THEN 'Active'   -- named scenario suppliers
       WHEN MOD(c.n * 11, 20) = 0        THEN 'Inactive'
       WHEN MOD(c.n * 11, 20) IN (1, 2)  THEN 'Under Review'
       ELSE 'Active' END                                                         AS VENDOR_STATUS,
  GET(ARRAY_CONSTRUCT('NET30','NET45','NET60','NET90'), MOD(c.n, 4))::VARCHAR    AS PAYMENT_TERMS,
  GET(ARRAY_CONSTRUCT('INR','CNY','VND','JPY','EUR','PLN','EUR','TRY','USD','MXN','BRL','KRW'), c.gi)::VARCHAR AS DEFAULT_CURRENCY,
  DATEADD(day, -(500 + MOD(c.n * 37, 2000)), a.A)                                AS CREATED_DATE
FROM calc c CROSS JOIN anchor a;

/* ===========================================================================
   SECTION 3 : SUPPLIER_PORTAL.SUPPLIER_PROFILE
   Controlled DISPLAY-NAME formatting drift vs ERP VENDOR_NAME.
   SUPPLIER_ID stays canonical - only presentation differs.
   =========================================================================== */
TRUNCATE TABLE SUPPLIER_PORTAL.SUPPLIER_PROFILE;
INSERT INTO SUPPLIER_PORTAL.SUPPLIER_PROFILE
  (SUPPLIER_ID, SUPPLIER_NAME, SUPPLIER_COUNTRY, PORTAL_STATUS, ONBOARDED_ON, PRIMARY_CONTACT_ROLE)
SELECT
  v.VENDOR_ID,
  CASE MOD(TO_NUMBER(SUBSTR(v.VENDOR_ID, 2)), 5)
    WHEN 0 THEN UPPER(REPLACE(v.VENDOR_NAME, ' Ltd', ' LIMITED'))
    WHEN 1 THEN REPLACE(v.VENDOR_NAME, ' ', '  ')            -- double-space drift
    WHEN 2 THEN UPPER(v.VENDOR_NAME)
    WHEN 3 THEN v.VENDOR_NAME || '.'                          -- trailing punctuation drift
    ELSE v.VENDOR_NAME
  END                                                          AS SUPPLIER_NAME,
  v.COUNTRY,
  CASE v.VENDOR_STATUS WHEN 'Active' THEN 'ENABLED'
                       WHEN 'Under Review' THEN 'RESTRICTED'
                       ELSE 'DISABLED' END                     AS PORTAL_STATUS,
  DATEADD(day, 30, v.CREATED_DATE)                             AS ONBOARDED_ON,
  GET(ARRAY_CONSTRUCT('Key Account Manager','Supply Chain Coordinator',
                      'Quality Manager','Logistics Lead','Commercial Manager'),
      MOD(TO_NUMBER(SUBSTR(v.VENDOR_ID, 2)), 5))::VARCHAR      AS PRIMARY_CONTACT_ROLE
FROM SAP_ERP.VENDOR_MASTER v;

/* ===========================================================================
   SECTION 4 : SAP_ERP.MATERIAL_MASTER  (1,000 parts, P001..P1000)
   P104 forced: Hydraulics / Valves, Critical, active, standard cost 412.50.
   P210 will act as the "volatile demand" part.
   =========================================================================== */
TRUNCATE TABLE SAP_ERP.MATERIAL_MASTER;
INSERT INTO SAP_ERP.MATERIAL_MASTER
  (MATERIAL_NO, MATERIAL_DESCRIPTION, PRODUCT_FAMILY, PRODUCT_CATEGORY,
   UNIT_OF_MEASURE, STANDARD_COST, WEIGHT, CRITICALITY, ACTIVE_FLAG)
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
  FROM TABLE(GENERATOR(ROWCOUNT => 1000))
),
calc AS (
  SELECT n,
         'P' || CASE WHEN n < 1000 THEN LPAD(n::VARCHAR, 3, '0') ELSE n::VARCHAR END AS mat,
         MOD(n * 7, 18) AS ci
  FROM s
)
SELECT
  c.mat,
  CASE WHEN c.n = 104
       THEN 'High-Precision Hydraulic Control Valve Assembly Type 104'
       ELSE GET(ARRAY_CONSTRUCT('Semiconductor','Connector','Sensor','Bearing','Gear','Shaft',
                                'Valve','Pump','Seal','Wiring Harness','Relay','Motor',
                                'Carton','Film','Pallet','Adhesive','Coating','Lubricant'), c.ci)::VARCHAR
            || ' ' ||
            GET(ARRAY_CONSTRUCT('Assembly','Module','Kit','Unit','Set','Housing'), MOD(c.n, 6))::VARCHAR
            || ' Type ' || LPAD((100 + MOD(c.n * 13, 900))::VARCHAR, 3, '0')
  END                                                                        AS MATERIAL_DESCRIPTION,
  CASE WHEN c.n = 104 THEN 'Hydraulics'
       ELSE GET(ARRAY_CONSTRUCT('Electronics','Electronics','Electronics','Mechanical','Mechanical','Mechanical',
                                'Hydraulics','Hydraulics','Hydraulics','Electrical','Electrical','Electrical',
                                'Packaging','Packaging','Packaging','Chemicals','Chemicals','Chemicals'), c.ci)::VARCHAR
  END                                                                        AS PRODUCT_FAMILY,
  CASE WHEN c.n = 104 THEN 'Valves'
       ELSE GET(ARRAY_CONSTRUCT('Semiconductors','Connectors','Sensors','Bearings','Gears','Shafts',
                                'Valves','Pumps','Seals','Wiring Harnesses','Relays','Motors',
                                'Cartons','Films','Pallets','Adhesives','Coatings','Lubricants'), c.ci)::VARCHAR
  END                                                                        AS PRODUCT_CATEGORY,
  CASE WHEN c.n = 104 THEN 'EA'
       ELSE GET(ARRAY_CONSTRUCT('EA','EA','EA','KG','M','L','BOX'), MOD(c.n, 7))::VARCHAR END AS UNIT_OF_MEASURE,
  CASE WHEN c.n = 104 THEN 412.50
       ELSE ROUND(35 + MOD(c.n * 137, 4600) + MOD(c.n, 97) / 100.0, 2) END    AS STANDARD_COST,
  CASE WHEN c.n = 104 THEN 2.450
       ELSE ROUND(0.05 + MOD(c.n * 17, 9000) / 1000.0, 3) END                 AS WEIGHT,
  CASE WHEN c.n = 104 THEN 'Critical'
       WHEN MOD(c.n * 3, 20) IN (0, 1)                THEN 'Critical'
       WHEN MOD(c.n * 3, 20) IN (2, 3, 4, 5)          THEN 'High'
       WHEN MOD(c.n * 3, 20) BETWEEN 6 AND 13         THEN 'Medium'
       ELSE 'Low' END                                                         AS CRITICALITY,
  CASE WHEN c.n = 104 THEN TRUE
       WHEN MOD(c.n * 7, 20) = 3 THEN FALSE ELSE TRUE END                     AS ACTIVE_FLAG
FROM calc c;

/* ===========================================================================
   SECTION 5 : TMS_LOGISTICS.CARRIER_MASTER  (20 carriers)
   CR11 = ocean carrier used by the flagship delayed shipment.
   =========================================================================== */
TRUNCATE TABLE TMS_LOGISTICS.CARRIER_MASTER;
INSERT INTO TMS_LOGISTICS.CARRIER_MASTER
  (CARRIER_CODE, CARRIER_NAME, TRANSPORT_MODE, REGION, SERVICE_LEVEL, ACTIVE_FLAG)
VALUES
  ('CR01','Deccan Road Freight',        'Road', 'APAC',  'Standard', TRUE),
  ('CR02','Konkan Express Logistics',   'Road', 'APAC',  'Priority', TRUE),
  ('CR03','SkyBridge Air Cargo',        'Air',  'APAC',  'Express',  TRUE),
  ('CR04','Pacific Wing Freight',       'Air',  'APAC',  'Priority', TRUE),
  ('CR05','Blue Meridian Shipping',     'Ocean','APAC',  'Standard', TRUE),
  ('CR06','Trans-Asia Rail Freight',    'Rail', 'APAC',  'Standard', TRUE),
  ('CR07','Rheinland Road Transport',   'Road', 'EMEA',  'Standard', TRUE),
  ('CR08','Nordstar Air Express',       'Air',  'EMEA',  'Express',  TRUE),
  ('CR09','Hanseatic Ocean Lines',      'Ocean','EMEA',  'Standard', TRUE),
  ('CR10','Vistula Rail Cargo',         'Rail', 'EMEA',  'Priority', TRUE),
  ('CR11','Eastwave Container Lines',   'Ocean','APAC',  'Standard', TRUE),
  ('CR12','Rio Grande Trucking',        'Road', 'AMER',  'Priority', TRUE),
  ('CR13','Great Lakes Air Freight',    'Air',  'AMER',  'Express',  TRUE),
  ('CR14','Atlantic Crest Shipping',    'Ocean','AMER',  'Standard', TRUE),
  ('CR15','Continental Rail Services',  'Rail', 'AMER',  'Standard', TRUE),
  ('CR16','Meridian Global Air',        'Air',  'Global','Priority', TRUE),
  ('CR17','Unified Road Network',       'Road', 'Global','Standard', TRUE),
  ('CR18','Oceanic Priority Lines',     'Ocean','Global','Priority', TRUE),
  ('CR19','Jetstream Cargo Partners',   'Air',  'Global','Express',  TRUE),
  ('CR20','Baltic Regional Haulage',    'Road', 'EMEA',  'Standard', FALSE);

/* ===========================================================================
   SECTION 6 : CRM_ORDERS.CUSTOMER_MASTER  (500 customers, C0001..C0500)
   C0001 / C0023 = Strategic P1, C0007 = Enterprise P2 : flagship customers.
   =========================================================================== */
TRUNCATE TABLE CRM_ORDERS.CUSTOMER_MASTER;
INSERT INTO CRM_ORDERS.CUSTOMER_MASTER
  (CUSTOMER_ID, CUSTOMER_NAME, CUSTOMER_SEGMENT, REGION, COUNTRY, PRIORITY_TIER, ACTIVE_FLAG)
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
  FROM TABLE(GENERATOR(ROWCOUNT => 500))
),
calc AS (
  SELECT n,
         MOD(n * 151, 500) AS nidx,
         MOD(n * 3, 12)    AS gi,
         CASE WHEN n IN (1, 23)                 THEN 'Strategic'
              WHEN n = 7                        THEN 'Enterprise'
              WHEN MOD(n, 20) IN (0, 1)         THEN 'Strategic'
              WHEN MOD(n, 20) IN (2, 3, 4, 5)   THEN 'Enterprise'
              WHEN MOD(n, 20) BETWEEN 6 AND 12  THEN 'Mid-Market'
              ELSE 'Standard' END               AS seg
  FROM s
)
SELECT
  'C' || LPAD(c.n::VARCHAR, 4, '0')                                            AS CUSTOMER_ID,
  GET(ARRAY_CONSTRUCT('Aurora','Bridgestone Works','Calderon','Drayton','Eastvale','Fairmount',
                      'Glenmoor','Havenport','Ironbridge','Juniper','Kingsley','Larkspur',
                      'Marchwood','Netherfield','Oakhurst','Pemberton','Quintrell','Ravenswood',
                      'Stonehaven','Thornbury','Uplands','Vanbrugh','Westmere','Yarrowfield',
                      'Zephyrline'), MOD(c.nidx, 25))::VARCHAR
  || ' ' ||
  GET(ARRAY_CONSTRUCT('Global','Industrial','Systems','Dynamics','Solutions'),
      MOD(FLOOR(c.nidx / 25), 5))::VARCHAR
  || ' ' ||
  GET(ARRAY_CONSTRUCT('Corp','Group','Holdings','Enterprises'),
      FLOOR(c.nidx / 125))::VARCHAR                                            AS CUSTOMER_NAME,
  c.seg                                                                        AS CUSTOMER_SEGMENT,
  GET(ARRAY_CONSTRUCT('APAC','APAC','APAC','APAC','EMEA','EMEA','EMEA','EMEA',
                      'AMER','AMER','AMER','APAC'), c.gi)::VARCHAR             AS REGION,
  GET(ARRAY_CONSTRUCT('India','China','Vietnam','Japan','Germany','Poland','Italy',
                      'Turkey','United States','Mexico','Brazil','South Korea'), c.gi)::VARCHAR AS COUNTRY,
  CASE c.seg WHEN 'Strategic' THEN 'P1' WHEN 'Enterprise' THEN 'P2'
             WHEN 'Mid-Market' THEN 'P3' ELSE 'P4' END                         AS PRIORITY_TIER,
  CASE WHEN c.n IN (1, 7, 23) THEN TRUE
       WHEN MOD(c.n * 13, 25) = 7 THEN FALSE ELSE TRUE END                     AS ACTIVE_FLAG
FROM calc c;

/* ===========================================================================
   SECTION 7 : PUBLIC.PART_SITE_COVERAGE  (2,000 active Part x Plant combos)
   Shared driver for inventory AND demand generation so every inventory
   position has matching demand history (needed for DOI / stockout risk).
   P104 is pinned to P01 (primary) and P03 (transfer source).
   =========================================================================== */
TRUNCATE TABLE PUBLIC.PART_SITE_COVERAGE;
INSERT INTO PUBLIC.PART_SITE_COVERAGE
  (PART_SEQ, MATERIAL_NO, PLANT_CODE, IS_PRIMARY_SITE, BASE_DAILY_DEMAND,
   DEMAND_PATTERN, INVENTORY_PATTERN, SAFETY_STOCK_DAYS)
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n
  FROM TABLE(GENERATOR(ROWCOUNT => 1000))
),
base AS (
  SELECT n,
         'P' || CASE WHEN n < 1000 THEN LPAD(n::VARCHAR, 3, '0') ELSE n::VARCHAR END AS mat,
         1 + MOD(n * 5, 12)      AS pa_raw,
         1 + MOD(n * 7 + 3, 12)  AS pb_raw
  FROM s
),
fixed AS (
  SELECT n, mat,
         CASE WHEN n = 104 THEN 1 ELSE pa_raw END AS pa,
         CASE WHEN n = 104 THEN 3
              WHEN pb_raw = pa_raw THEN 1 + MOD(pa_raw, 12)
              ELSE pb_raw END                     AS pb
  FROM base
),
slots AS (
  SELECT n, mat, pa AS pl, TRUE  AS is_primary, 1 AS slot FROM fixed
  UNION ALL
  SELECT n, mat, pb AS pl, FALSE AS is_primary, 2 AS slot FROM fixed
)
SELECT
  sl.n,
  sl.mat,
  'P' || LPAD(sl.pl::VARCHAR, 2, '0')                                          AS PLANT_CODE,
  sl.is_primary,
  CASE WHEN sl.n = 104 AND sl.pl = 1 THEN 700
       WHEN sl.n = 104 AND sl.pl = 3 THEN 120
       WHEN sl.slot = 1 THEN 5 + MOD(sl.n * 29 + sl.pl * 7, 400)
       ELSE GREATEST(2, ROUND((5 + MOD(sl.n * 29 + sl.pl * 7, 400)) * 0.4)) END AS BASE_DAILY_DEMAND,
  CASE WHEN sl.n = 104 AND sl.pl = 1 THEN 'Stable'
       WHEN sl.n = 210 AND sl.slot = 1 THEN 'Volatile'
       /* hash-based selection: a linear form such as MOD(n*3 + pl, 8) collapses
          into a few residue classes because pl is itself derived from n, which
          left 'Increasing' with 1 combo and 'Forecast-Over' with none. */
       ELSE GET(ARRAY_CONSTRUCT('Stable','Seasonal','Volatile','Increasing','Declining',
                                'Low-Volume','Forecast-Under','Forecast-Over'),
                MOD(ABS(HASH(sl.mat, sl.pl, 'dpat')), 8))::VARCHAR END          AS DEMAND_PATTERN,
  CASE WHEN sl.n = 104 AND sl.pl = 1 THEN 'Healthy'
       WHEN sl.n = 104 AND sl.pl = 3 THEN 'Excess'
       WHEN sl.n = 318 AND sl.slot = 1 THEN 'Excess'      -- excess-inventory scenario
       WHEN sl.n = 527 AND sl.slot = 1 THEN 'Stockout'    -- likely-stockout scenario
       WHEN sl.pl = 7 THEN 'Excess'                       -- P07: high inventory, weak demand
       ELSE GET(ARRAY_CONSTRUCT('Healthy','Healthy','Healthy','Near-Safety','Stockout','Excess',
                                'Declining','Slow-Moving'),
                MOD(ABS(HASH(sl.mat, sl.pl, 'ipat')), 8))::VARCHAR END          AS INVENTORY_PATTERN,
  CASE WHEN sl.n = 104 AND sl.pl = 1 THEN 4.3
       WHEN sl.n = 104 AND sl.pl = 3 THEN 20.8
       ELSE 3 + MOD(sl.n + sl.pl, 10) END                                       AS SAFETY_STOCK_DAYS
FROM slots sl;

/* ===========================================================================
   SECTION 8 : SAP_ERP.SUPPLIER_MATERIAL  (approved sourcing relationships)
   Primary supplier for every part; extra approved alternates for Critical /
   High criticality parts only (not every supplier can supply every part).
   FLAGSHIP: S017 primary for P104 (cheaper, 28d lead), S042 alternate
             (pricier, 7d lead, 4,500 units/week capacity).
   =========================================================================== */
TRUNCATE TABLE SAP_ERP.SUPPLIER_MATERIAL;
INSERT INTO SAP_ERP.SUPPLIER_MATERIAL
  (VENDOR_ID, MATERIAL_NO, IS_PRIMARY_SUPPLIER, AGREED_UNIT_PRICE,
   CONTRACT_LEAD_TIME_DAYS, MINIMUM_ORDER_QTY, MAX_WEEKLY_SUPPLY_QTY,
   CURRENCY, VALID_FROM, VALID_TO)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
m AS (
  SELECT MATERIAL_NO, STANDARD_COST, CRITICALITY,
         TO_NUMBER(SUBSTR(MATERIAL_NO, 2)) AS n
  FROM SAP_ERP.MATERIAL_MASTER
),
pick AS (
  /* primary source */
  SELECT n, MATERIAL_NO, STANDARD_COST, CRITICALITY, TRUE AS is_primary,
         CASE WHEN n = 104 THEN 17
              WHEN 1 + MOD(n * 13, 100) IN (20,40,60,80,100) THEN 1 + MOD(n * 13, 100) - 3
              ELSE 1 + MOD(n * 13, 100) END AS vn
  FROM m
  UNION ALL
  /* first alternate - Critical & High parts */
  SELECT n, MATERIAL_NO, STANDARD_COST, CRITICALITY, FALSE,
         CASE WHEN n = 104 THEN 42
              WHEN 1 + MOD(n * 31 + 7, 100) IN (20,40,60,80,100) THEN 1 + MOD(n * 31 + 7, 100) - 3
              ELSE 1 + MOD(n * 31 + 7, 100) END
  FROM m
  WHERE CRITICALITY IN ('Critical','High')
  UNION ALL
  /* second alternate - Critical parts only (excluding P104, kept deliberately dual-sourced) */
  SELECT n, MATERIAL_NO, STANDARD_COST, CRITICALITY, FALSE,
         CASE WHEN 1 + MOD(n * 53 + 19, 100) IN (20,40,60,80,100) THEN 1 + MOD(n * 53 + 19, 100) - 3
              ELSE 1 + MOD(n * 53 + 19, 100) END
  FROM m
  WHERE CRITICALITY = 'Critical' AND n <> 104
),
dedup AS (
  SELECT p.*, 'S' || LPAD(p.vn::VARCHAR, 3, '0') AS VENDOR_ID
  FROM pick p
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.MATERIAL_NO, p.vn
                             ORDER BY p.is_primary DESC) = 1
)
SELECT
  d.VENDOR_ID,
  d.MATERIAL_NO,
  d.is_primary,
  CASE WHEN d.n = 104 AND d.VENDOR_ID = 'S017' THEN 395.00
       WHEN d.n = 104 AND d.VENDOR_ID = 'S042' THEN 431.00
       WHEN d.is_primary THEN ROUND(d.STANDARD_COST * 0.94, 2)
       ELSE ROUND(d.STANDARD_COST * (1.04 + MOD(ABS(HASH(d.MATERIAL_NO, d.VENDOR_ID, 'pr')), 9) / 100.0), 2)
  END                                                                          AS AGREED_UNIT_PRICE,
  CASE WHEN d.n = 104 AND d.VENDOR_ID = 'S017' THEN 28
       WHEN d.n = 104 AND d.VENDOR_ID = 'S042' THEN 7
       WHEN d.is_primary THEN 7 + MOD(d.n * 7, 35)
       ELSE 5 + MOD(d.n * 11, 30) END                                          AS CONTRACT_LEAD_TIME_DAYS,
  CASE WHEN d.n = 104 AND d.VENDOR_ID = 'S017' THEN 500
       WHEN d.n = 104 AND d.VENDOR_ID = 'S042' THEN 250
       ELSE GET(ARRAY_CONSTRUCT(100, 250, 500, 1000), MOD(d.n, 4))::NUMBER END  AS MINIMUM_ORDER_QTY,
  CASE WHEN d.n = 104 AND d.VENDOR_ID = 'S017' THEN 6000
       WHEN d.n = 104 AND d.VENDOR_ID = 'S042' THEN 4500
       ELSE 1000 + MOD(d.n * 211, 7000) END                                    AS MAX_WEEKLY_SUPPLY_QTY,
  v.DEFAULT_CURRENCY                                                           AS CURRENCY,
  DATEADD(day, -900, a.A)                                                      AS VALID_FROM,
  DATEADD(day,  400, a.A)                                                      AS VALID_TO
FROM dedup d
JOIN SAP_ERP.VENDOR_MASTER v ON v.VENDOR_ID = d.VENDOR_ID
CROSS JOIN anchor a;

/* ===========================================================================
   SECTION 9 : SAP_ERP.PURCHASE_ORDER_LINES  (~55,000 lines / 22,000 POs)
   1-4 lines per PO. ~4% cancelled. Realistic OPEN / DELIVERED /
   PARTIALLY_DELIVERED / OVERDUE mix. ~2% NULL CONFIRMATION_DATE.
   P104@P01 bulk lines are deliberately forced to historical, non-open
   statuses so the flagship delayed inbound shipment is the ONLY open,
   delayed S017/P104/P01 inbound.
   =========================================================================== */
TRUNCATE TABLE SAP_ERP.PURCHASE_ORDER_LINES;
INSERT INTO SAP_ERP.PURCHASE_ORDER_LINES
  (PO_NUMBER, PO_LINE_NUMBER, VENDOR_ID, MATERIAL_NO, PLANT_CODE, ORDER_DATE,
   CONFIRMATION_DATE, PROMISED_DATE, ORDER_QTY, UNIT_PRICE, CURRENCY, PO_STATUS)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
pos AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS po_seq
  FROM TABLE(GENERATOR(ROWCOUNT => 22000))
),
lines AS (
  SELECT p.po_seq, f.value::NUMBER AS line_no
  FROM pos p,
       LATERAL FLATTEN(input => ARRAY_GENERATE_RANGE(1, 2 + MOD(ABS(HASH(p.po_seq, 'L')), 4))) f
),
cov AS (
  SELECT ROW_NUMBER() OVER (ORDER BY MATERIAL_NO, PLANT_CODE) AS rn, MATERIAL_NO, PLANT_CODE
  FROM PUBLIC.PART_SITE_COVERAGE
),
picked AS (
  SELECT l.po_seq, l.line_no, c.MATERIAL_NO, c.PLANT_CODE,
         (c.MATERIAL_NO = 'P104' AND c.PLANT_CODE = 'P01') AS is_flagship_combo
  FROM lines l
  JOIN cov c ON c.rn = 1 + MOD(ABS(HASH(l.po_seq, l.line_no, 'cmb')), 2000)
),
sourced AS (
  SELECT p.*, sm.VENDOR_ID, sm.AGREED_UNIT_PRICE, sm.CONTRACT_LEAD_TIME_DAYS, sm.CURRENCY
  FROM picked p
  JOIN SAP_ERP.SUPPLIER_MATERIAL sm ON sm.MATERIAL_NO = p.MATERIAL_NO
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.po_seq, p.line_no
                             ORDER BY ABS(HASH(p.po_seq, p.line_no, sm.VENDOR_ID, 'vend'))) = 1
),
dated AS (
  SELECT s.*,
         a.A,
         MOD(ABS(HASH(s.po_seq, s.line_no, 'st')), 100) AS bucket,
         DATEADD(day, -(3 + MOD(ABS(HASH(s.po_seq, 'od')), 545)), a.A) AS order_date_raw
  FROM sourced s CROSS JOIN anchor a
),
final AS (
  SELECT d.*,
         CASE WHEN d.is_flagship_combo
              THEN DATEADD(day, -(60 + MOD(ABS(HASH(d.po_seq, 'fo')), 400)), d.A)
              ELSE d.order_date_raw END AS order_date
  FROM dated d
),
final2 AS (
  SELECT f.*,
         DATEADD(day,
                 f.CONTRACT_LEAD_TIME_DAYS + MOD(ABS(HASH(f.po_seq, f.line_no, 'pd')), 7) - 3,
                 f.order_date) AS promised_date
  FROM final f
)
SELECT
  'PO' || LPAD(f.po_seq::VARCHAR, 6, '0')                                      AS PO_NUMBER,
  f.line_no                                                                    AS PO_LINE_NUMBER,
  f.VENDOR_ID,
  f.MATERIAL_NO,
  f.PLANT_CODE,
  f.order_date                                                                 AS ORDER_DATE,
  CASE WHEN MOD(ABS(HASH(f.po_seq, f.line_no, 'cf')), 50) = 0 THEN NULL
       ELSE DATEADD(day, 1 + MOD(ABS(HASH(f.po_seq, 'cd')), 4), f.order_date) END AS CONFIRMATION_DATE,
  f.promised_date                                                              AS PROMISED_DATE,
  50 + MOD(ABS(HASH(f.po_seq, f.line_no, 'q')), 1950)                          AS ORDER_QTY,
  ROUND(f.AGREED_UNIT_PRICE * (0.97 + MOD(ABS(HASH(f.po_seq, f.line_no, 'up')), 7) / 100.0), 2) AS UNIT_PRICE,
  f.CURRENCY,
  CASE
    WHEN f.is_flagship_combo THEN
         CASE WHEN f.bucket < 4  THEN 'CANCELLED'
              WHEN f.bucket < 88 THEN 'DELIVERED'
              ELSE 'PARTIALLY_DELIVERED' END
    WHEN f.bucket < 4 THEN 'CANCELLED'
    WHEN f.promised_date < f.A THEN
         CASE WHEN f.bucket < 78 THEN 'DELIVERED'
              WHEN f.bucket < 90 THEN 'PARTIALLY_DELIVERED'
              ELSE 'OVERDUE' END
    ELSE 'OPEN'
  END                                                                          AS PO_STATUS
FROM final2 f;

/* ===========================================================================
   SECTION 10 : TMS_LOGISTICS.SHIPMENTS  (~54,000 shipment lines)
   Built from non-cancelled PO lines (95% of them ship). ~8% of lines are
   split across TWO shipments (multiple shipments per PO line).
   Distribution targets: ~15% early, ~55% on time, ~18% late, rest in
   transit / planned. Landed-cost components populated.
   =========================================================================== */
TRUNCATE TABLE TMS_LOGISTICS.SHIPMENTS;
INSERT INTO TMS_LOGISTICS.SHIPMENTS
  (SHIPMENT_ID, SHIPMENT_LINE_NUMBER, PO_REF, PO_LINE_REF, SUPPLIER_CODE, ITEM_CODE,
   DESTINATION_SITE, CARRIER_CODE, SHIP_DATE, EXPECTED_DELIVERY_DATE,
   ACTUAL_DELIVERY_DATE, PROJECTED_DELIVERY_DATE, SHIPPED_QTY, RECEIVED_QTY,
   FREIGHT_COST, DUTY_COST, HANDLING_COST, OTHER_LOGISTICS_COST,
   TRANSPORT_MODE, SHIPMENT_STATUS)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
legs AS (SELECT 1 AS leg UNION ALL SELECT 2),
elig AS (
  SELECT p.*,
         TO_NUMBER(SUBSTR(p.PO_NUMBER, 3)) AS po_seq,
         (MOD(ABS(HASH(p.PO_NUMBER, p.PO_LINE_NUMBER, 'split')), 100) < 8) AS is_split
  FROM SAP_ERP.PURCHASE_ORDER_LINES p
  WHERE p.PO_STATUS <> 'CANCELLED'
    AND MOD(ABS(HASH(p.PO_NUMBER, p.PO_LINE_NUMBER, 'ship')), 100) < 95
),
expanded AS (
  SELECT e.*, l.leg
  FROM elig e JOIN legs l ON (l.leg = 1 OR e.is_split)
),
enriched AS (
  SELECT x.*,
         a.A,
         'CR' || LPAD((1 + MOD(ABS(HASH(x.PO_NUMBER, x.PO_LINE_NUMBER, 'car')), 20))::VARCHAR, 2, '0') AS carrier,
         mm.WEIGHT,
         v.COUNTRY AS vendor_country,
         pl.COUNTRY AS plant_country,
         MOD(ABS(HASH(x.PO_NUMBER, x.PO_LINE_NUMBER, x.leg, 'h')), 100) AS h,
         MOD(ABS(HASH(x.PO_NUMBER, x.PO_LINE_NUMBER, x.leg, 'dd')), 100) AS dbucket,
         TO_NUMBER(SUBSTR(x.VENDOR_ID, 2)) AS vn
  FROM expanded x
  CROSS JOIN anchor a
  JOIN SAP_ERP.MATERIAL_MASTER mm ON mm.MATERIAL_NO = x.MATERIAL_NO
  JOIN SAP_ERP.VENDOR_MASTER   v  ON v.VENDOR_ID   = x.VENDOR_ID
  JOIN SAP_ERP.PLANT_MASTER    pl ON pl.PLANT_CODE = x.PLANT_CODE
),
moded AS (
  SELECT e.*, cm.TRANSPORT_MODE,
         CASE cm.TRANSPORT_MODE
           WHEN 'Air'   THEN 4  + MOD(e.h, 4)
           WHEN 'Road'  THEN 3  + MOD(e.h, 6)
           WHEN 'Rail'  THEN 7  + MOD(e.h, 7)
           ELSE              18 + MOD(e.h, 14)
         END AS transit_days
  FROM enriched e
  JOIN TMS_LOGISTICS.CARRIER_MASTER cm ON cm.CARRIER_CODE = e.carrier
),
qty AS (
  SELECT m.*,
         CASE WHEN NOT m.is_split THEN m.ORDER_QTY
              WHEN m.leg = 1      THEN ROUND(m.ORDER_QTY * 0.6)
              ELSE m.ORDER_QTY - ROUND(m.ORDER_QTY * 0.6) END AS shipped_qty,
         /* Leg 1 ships so that the carrier commitment (EXPECTED_DELIVERY_DATE)
            lands exactly on the ERP PROMISED_DATE - this is what makes governed
            OTD (actual vs promised) meaningful. A split leg 2 ships 5 days
            later and is therefore genuinely late against the same promise. */
         DATEADD(day,
                 -m.transit_days + CASE WHEN m.leg = 2 THEN 5 ELSE 0 END,
                 m.PROMISED_DATE) AS ship_date
  FROM moded m
),
dates AS (
  SELECT q.*,
         DATEADD(day, q.transit_days, q.ship_date) AS expected_dd,
         /* Supplier-differentiated delivery reliability. Cut points are
            percentiles of dbucket (0-99):
              S017, S088  poor        ->  5% early / 50% on time / 45% late
              S055        deteriorating->  8% early / 60% on time / 32% late
              S011, S042  strong      -> 22% early / 73% on time /  5% late
              all others              -> 15% early / 67% on time / 18% late   */
         CASE WHEN q.vn IN (17, 88) THEN 5
              WHEN q.vn = 55        THEN 8
              WHEN q.vn IN (11, 42) THEN 22
              ELSE 15 END AS early_cut,
         CASE WHEN q.vn IN (17, 88) THEN 55
              WHEN q.vn = 55        THEN 68
              WHEN q.vn IN (11, 42) THEN 95
              ELSE 82 END AS ontime_cut
  FROM qty q
),
deltas AS (
  SELECT d.*,
         CASE WHEN d.dbucket < d.early_cut  THEN -(1 + MOD(d.h, 4))   -- early
              WHEN d.dbucket < d.ontime_cut THEN 0                    -- on time
              ELSE (1 + MOD(d.h, 12)) END AS delivery_delta           -- late
  FROM dates d
),
resolved AS (
  SELECT d.*,
         DATEADD(day, d.delivery_delta, d.expected_dd) AS candidate_actual,
         CASE
           WHEN d.PO_STATUS IN ('OPEN','OVERDUE') THEN 'OPEN_LEG'
           WHEN DATEADD(day, d.delivery_delta, d.expected_dd) > d.A THEN 'OPEN_LEG'
           WHEN d.PO_STATUS = 'PARTIALLY_DELIVERED' THEN 'PARTIAL'
           ELSE 'DELIVERED'
         END AS leg_state
  FROM deltas d
)
SELECT
  'SH' || LPAD((r.po_seq + IFF(r.leg = 2, 500000, 0))::VARCHAR, 6, '0')        AS SHIPMENT_ID,
  r.PO_LINE_NUMBER                                                             AS SHIPMENT_LINE_NUMBER,
  r.PO_NUMBER                                                                  AS PO_REF,
  r.PO_LINE_NUMBER                                                             AS PO_LINE_REF,
  r.VENDOR_ID                                                                  AS SUPPLIER_CODE,
  r.MATERIAL_NO                                                                AS ITEM_CODE,
  r.PLANT_CODE                                                                 AS DESTINATION_SITE,
  r.carrier                                                                    AS CARRIER_CODE,
  r.ship_date                                                                  AS SHIP_DATE,
  r.expected_dd                                                                AS EXPECTED_DELIVERY_DATE,
  CASE WHEN r.leg_state = 'OPEN_LEG' THEN NULL ELSE r.candidate_actual END      AS ACTUAL_DELIVERY_DATE,
  CASE WHEN r.leg_state = 'OPEN_LEG'
       THEN GREATEST(DATEADD(day, MOD(r.h, 7), r.expected_dd), DATEADD(day, 1, r.A))
       ELSE r.candidate_actual END                                             AS PROJECTED_DELIVERY_DATE,
  r.shipped_qty                                                                AS SHIPPED_QTY,
  CASE WHEN r.leg_state = 'OPEN_LEG' THEN 0
       WHEN r.leg_state = 'PARTIAL'  THEN ROUND(r.shipped_qty * (0.55 + MOD(r.h, 35) / 100.0))
       ELSE r.shipped_qty END                                                  AS RECEIVED_QTY,
  ROUND(r.shipped_qty * r.WEIGHT *
        CASE r.TRANSPORT_MODE WHEN 'Air' THEN 3.20 WHEN 'Road' THEN 0.80
                              WHEN 'Rail' THEN 0.50 ELSE 0.35 END, 2)          AS FREIGHT_COST,
  CASE WHEN r.vendor_country = r.plant_country THEN 0
       ELSE ROUND(r.shipped_qty * r.UNIT_PRICE * 0.065, 2) END                 AS DUTY_COST,
  ROUND(250 + r.shipped_qty * 0.35, 2)                                         AS HANDLING_COST,
  CASE WHEN MOD(r.h, 20) = 0 THEN NULL
       ELSE ROUND(r.shipped_qty * r.UNIT_PRICE * 0.004, 2) END                 AS OTHER_LOGISTICS_COST,
  r.TRANSPORT_MODE,
  CASE WHEN r.leg_state = 'OPEN_LEG' AND r.ship_date > r.A THEN 'PLANNED'
       WHEN r.leg_state = 'OPEN_LEG' THEN 'IN_TRANSIT'
       WHEN r.leg_state = 'PARTIAL'  THEN 'PARTIAL'
       ELSE 'DELIVERED' END                                                    AS SHIPMENT_STATUS
FROM resolved r;

/* ===========================================================================
   SECTION 11 : TMS_LOGISTICS.TRANSPORT_OPTIONS
   Lane catalogue. FLAGSHIP: APAC -> P01 Air lane, expedited transit 4 days
   (arrival anchor+4, i.e. before the first flagship order due at anchor+12);
   APAC -> P01 Ocean lane normal 21 days matches the delayed shipment.
   =========================================================================== */
TRUNCATE TABLE TMS_LOGISTICS.TRANSPORT_OPTIONS;
INSERT INTO TMS_LOGISTICS.TRANSPORT_OPTIONS
  (ORIGIN_REGION, DESTINATION_PLANT, TRANSPORT_MODE, NORMAL_TRANSIT_DAYS,
   EXPEDITED_TRANSIT_DAYS, NORMAL_COST_FACTOR, EXPEDITE_COST_FACTOR, ACTIVE_FLAG)
WITH regions AS (
  SELECT 'APAC' AS r UNION ALL SELECT 'EMEA' UNION ALL SELECT 'AMER'
),
modes AS (
  SELECT 'Air' AS m UNION ALL SELECT 'Ocean' UNION ALL SELECT 'Road' UNION ALL SELECT 'Rail'
),
lanes AS (
  SELECT rg.r, p.PLANT_CODE, md.m, (rg.r = p.REGION) AS same_region
  FROM regions rg
  CROSS JOIN SAP_ERP.PLANT_MASTER p
  CROSS JOIN modes md
  WHERE md.m IN ('Air','Ocean') OR rg.r = p.REGION      -- Road/Rail only intra-region
)
SELECT
  l.r                                                                          AS ORIGIN_REGION,
  l.PLANT_CODE                                                                 AS DESTINATION_PLANT,
  l.m                                                                          AS TRANSPORT_MODE,
  CASE l.m WHEN 'Air'   THEN IFF(l.same_region,  9, 12)
           WHEN 'Ocean' THEN IFF(l.same_region, 21, 34)
           WHEN 'Road'  THEN 5
           ELSE 9 END                                                          AS NORMAL_TRANSIT_DAYS,
  CASE l.m WHEN 'Air'   THEN IFF(l.same_region,  4,  6)
           WHEN 'Ocean' THEN IFF(l.same_region, 12, 20)
           WHEN 'Road'  THEN 3
           ELSE 6 END                                                          AS EXPEDITED_TRANSIT_DAYS,
  1.000                                                                        AS NORMAL_COST_FACTOR,
  CASE l.m WHEN 'Air' THEN 2.600 WHEN 'Ocean' THEN 1.850
           WHEN 'Road' THEN 1.600 ELSE 1.450 END                               AS EXPEDITE_COST_FACTOR,
  CASE WHEN l.r = 'APAC' AND l.PLANT_CODE = 'P01' THEN TRUE      -- flagship lanes always active
       WHEN MOD(ABS(HASH(l.r, l.PLANT_CODE, l.m, 'act')), 17) = 0 THEN FALSE
       ELSE TRUE END                                                           AS ACTIVE_FLAG
FROM lanes l;

/* ===========================================================================
   SECTION 12 : TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS
   Intra-region lanes only. FLAGSHIP: P03 -> P01 road, 3 days, 5,000 max.
   =========================================================================== */
TRUNCATE TABLE TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS;
INSERT INTO TMS_LOGISTICS.INTERPLANT_TRANSFER_OPTIONS
  (ORIGIN_PLANT, DESTINATION_PLANT, TRANSPORT_MODE, TRANSIT_DAYS, COST_PER_UNIT,
   FIXED_TRANSFER_COST, MAX_TRANSFER_QTY, ACTIVE_FLAG)
WITH pairs AS (
  SELECT o.PLANT_CODE AS op, d.PLANT_CODE AS dp,
         (o.COUNTRY = d.COUNTRY) AS same_country,
         MOD(ABS(HASH(o.PLANT_CODE, d.PLANT_CODE, 'tr')), 100) AS h
  FROM SAP_ERP.PLANT_MASTER o
  JOIN SAP_ERP.PLANT_MASTER d
    ON o.REGION = d.REGION AND o.PLANT_CODE <> d.PLANT_CODE
)
SELECT
  p.op, p.dp,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN 'Road'
       WHEN p.same_country THEN 'Road' ELSE 'Air' END                          AS TRANSPORT_MODE,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN 3
       WHEN p.same_country THEN 2 + MOD(p.h, 3)
       ELSE 6 + MOD(p.h, 4) END                                                AS TRANSIT_DAYS,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN 45.00
       ELSE ROUND(12 + MOD(p.h, 60) + MOD(p.h, 7) / 10.0, 2) END               AS COST_PER_UNIT,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN 25000.00
       ELSE ROUND(5000 + MOD(p.h * 311, 30000), 2) END                         AS FIXED_TRANSFER_COST,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN 5000
       ELSE 2000 + MOD(p.h * 97, 6000) END                                     AS MAX_TRANSFER_QTY,
  CASE WHEN p.op = 'P03' AND p.dp = 'P01' THEN TRUE
       WHEN MOD(p.h, 13) = 0 THEN FALSE ELSE TRUE END                          AS ACTIVE_FLAG
FROM pairs p;

/* ===========================================================================
   SECTION 13 : WMS_INVENTORY.INVENTORY_SNAPSHOTS  (2,000 combos x 52 weeks
                = 104,000 rows). Latest SNAPSHOT_DATE = DATASET_ANCHOR_DATE.
   Patterns: Healthy / Near-Safety / Stockout / Excess / Declining /
             Slow-Moving / Increasing.
   =========================================================================== */
TRUNCATE TABLE WMS_INVENTORY.INVENTORY_SNAPSHOTS;
INSERT INTO WMS_INVENTORY.INVENTORY_SNAPSHOTS
  (SITE_ID, SKU, SNAPSHOT_DATE, ON_HAND_QTY, RESERVED_QTY, AVAILABLE_QTY,
   SAFETY_STOCK_QTY, IN_TRANSIT_QTY, INVENTORY_STATUS)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
weeks AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS w
  FROM TABLE(GENERATOR(ROWCOUNT => 52))
),
grid AS (
  SELECT c.MATERIAL_NO, c.PLANT_CODE, c.BASE_DAILY_DEMAND AS base,
         c.INVENTORY_PATTERN AS pat, c.SAFETY_STOCK_DAYS AS sdays,
         w.w, DATEADD(day, -7 * w.w, a.A) AS snap_date,
         MOD(ABS(HASH(c.MATERIAL_NO, c.PLANT_CODE, w.w, 'inv')), 100) AS h
  FROM PUBLIC.PART_SITE_COVERAGE c
  CROSS JOIN weeks w
  CROSS JOIN anchor a
),
calc AS (
  SELECT g.*,
         CASE WHEN g.MATERIAL_NO = 'P104' AND g.PLANT_CODE = 'P01' THEN 3000
              WHEN g.MATERIAL_NO = 'P104' AND g.PLANT_CODE = 'P03' THEN 2500
              ELSE GREATEST(1, ROUND(g.base * g.sdays)) END AS safety,
         CASE g.pat
           WHEN 'Healthy'     THEN 11.0 + MOD(g.h, 5)
           WHEN 'Near-Safety' THEN g.sdays + 0.4 + MOD(g.h, 2)
           WHEN 'Stockout'    THEN IFF(g.w < 3, 0.0, 1.0 + MOD(g.h, 4))
           WHEN 'Excess'      THEN 46.0 + MOD(g.h, 12)
           WHEN 'Declining'   THEN 6.0 + g.w * 0.5
           WHEN 'Increasing'  THEN GREATEST(4.0, 30.0 - g.w * 0.4)
           WHEN 'Slow-Moving' THEN 62.0 + MOD(g.h, 20)
           ELSE 12.0 + MOD(g.h, 6)
         END AS cover_days
  FROM grid g
),
qtys AS (
  SELECT c.*,
         GREATEST(0, ROUND(c.base * c.cover_days * (0.94 + MOD(c.h, 13) / 100.0))) AS on_hand
  FROM calc c
),
final AS (
  SELECT q.*,
         ROUND(q.on_hand * MOD(q.h, 15) / 100.0) AS reserved
  FROM qtys q
)
SELECT
  f.PLANT_CODE                                                                 AS SITE_ID,
  f.MATERIAL_NO                                                                AS SKU,
  f.snap_date                                                                  AS SNAPSHOT_DATE,
  f.on_hand                                                                    AS ON_HAND_QTY,
  f.reserved                                                                   AS RESERVED_QTY,
  f.on_hand - f.reserved                                                       AS AVAILABLE_QTY,
  f.safety                                                                     AS SAFETY_STOCK_QTY,
  ROUND(f.base * MOD(f.h, 12))                                                 AS IN_TRANSIT_QTY,
  CASE WHEN f.on_hand - f.reserved <= 0                    THEN 'STOCKOUT'
       WHEN f.on_hand - f.reserved <  f.safety             THEN 'BELOW_SAFETY'
       WHEN f.on_hand - f.reserved <  f.safety * 1.15      THEN 'AT_SAFETY'
       WHEN f.on_hand - f.reserved >  f.safety * 4         THEN 'EXCESS'
       ELSE 'HEALTHY' END                                                      AS INVENTORY_STATUS
FROM final f;

/* ===========================================================================
   SECTION 14a : DEMAND_PLANNING.DEMAND_HISTORY - bulk
   Same 2,000 Part x Plant combos as inventory, 60 daily history rows each
   (anchor-1 .. anchor-60) = ~120,000 rows. P104/P01 excluded here and
   generated deterministically in 14b.
   =========================================================================== */
TRUNCATE TABLE DEMAND_PLANNING.DEMAND_HISTORY;
INSERT INTO DEMAND_PLANNING.DEMAND_HISTORY
  (PART_ID, LOCATION_ID, DEMAND_DATE, FORECAST_QTY, ACTUAL_DEMAND_QTY,
   FORECAST_VERSION, DEMAND_SOURCE, DEMAND_PATTERN)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS d
  FROM TABLE(GENERATOR(ROWCOUNT => 60))
),
grid AS (
  SELECT c.MATERIAL_NO, c.PLANT_CODE, c.BASE_DAILY_DEMAND AS base,
         c.DEMAND_PATTERN AS pat, dy.d,
         DATEADD(day, -dy.d, a.A) AS ddate,
         MOD(ABS(HASH(c.MATERIAL_NO, c.PLANT_CODE, dy.d, 'dm')), 100) AS h
  FROM PUBLIC.PART_SITE_COVERAGE c
  CROSS JOIN days dy
  CROSS JOIN anchor a
  WHERE NOT (c.MATERIAL_NO = 'P104' AND c.PLANT_CODE = 'P01')
),
shaped AS (
  SELECT g.*,
         CASE g.pat
           WHEN 'Stable'         THEN 1.0 + (MOD(g.h, 21) - 10) / 100.0
           WHEN 'Seasonal'       THEN 1.0 + 0.35 * SIN(2 * PI() * g.d / 30.0) + (MOD(g.h, 11) - 5) / 100.0
           WHEN 'Volatile'       THEN 1.0 + (MOD(g.h, 81) - 40) / 100.0
           WHEN 'Increasing'     THEN GREATEST(0.4, 1.40 - g.d * 0.006)
           WHEN 'Declining'      THEN GREATEST(0.4, 0.70 + g.d * 0.006)
           WHEN 'Low-Volume'     THEN IFF(MOD(g.h, 3) = 0, 0.0, 1.0)
           WHEN 'Forecast-Under' THEN 1.0 + (MOD(g.h, 15) - 7) / 100.0
           ELSE                       1.0 + (MOD(g.h, 15) - 7) / 100.0
         END AS factor
  FROM grid g
),
actuals AS (
  SELECT s.*, GREATEST(0, ROUND(s.base * s.factor)) AS actual_qty FROM shaped s
)
SELECT
  a.MATERIAL_NO                                                                AS PART_ID,
  a.PLANT_CODE                                                                 AS LOCATION_ID,
  a.ddate                                                                      AS DEMAND_DATE,
  CASE a.pat
    WHEN 'Forecast-Under' THEN GREATEST(0, ROUND(a.actual_qty * 0.78))
    WHEN 'Forecast-Over'  THEN GREATEST(0, ROUND(a.actual_qty * 1.28))
    ELSE GREATEST(0, ROUND(a.actual_qty * (0.90 + MOD(a.h, 21) / 100.0)))
  END                                                                          AS FORECAST_QTY,
  a.actual_qty                                                                 AS ACTUAL_DEMAND_QTY,
  'FY' || YEAR(a.ddate)::VARCHAR || '-M' || LPAD(MONTH(a.ddate)::VARCHAR, 2, '0')
        || '-V' || (1 + MOD(a.h, 3))::VARCHAR                                  AS FORECAST_VERSION,
  GET(ARRAY_CONSTRUCT('Statistical Forecast','Sales Input','ML Model','Customer Commit'),
      MOD(a.h, 4))::VARCHAR                                                    AS DEMAND_SOURCE,
  a.pat                                                                        AS DEMAND_PATTERN
FROM actuals a;

/* ===========================================================================
   SECTION 14b : DEMAND_PLANNING.DEMAND_HISTORY - flagship P104 / P01
   Realistic day-to-day variation around 700 units/day. The most recent
   30 historical days (anchor-1 .. anchor-30) sum to EXACTLY 21,000 so the
   governed 30-day average daily demand is exactly 700 units/day.
   Day 30 absorbs the rounding remainder.
   =========================================================================== */
INSERT INTO DEMAND_PLANNING.DEMAND_HISTORY
  (PART_ID, LOCATION_ID, DEMAND_DATE, FORECAST_QTY, ACTUAL_DEMAND_QTY,
   FORECAST_VERSION, DEMAND_SOURCE, DEMAND_PATTERN)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS d
  FROM TABLE(GENERATOR(ROWCOUNT => 60))
),
raw AS (
  SELECT d,
         CASE WHEN d = 30 THEN NULL
              ELSE 700 + (MOD(ABS(HASH(d, 'p104dm')), 121) - 60) END AS q
  FROM days
),
balance AS (
  SELECT 21000 - SUM(q) AS q30 FROM raw WHERE d BETWEEN 1 AND 29
),
final AS (
  SELECT r.d, COALESCE(r.q, b.q30) AS actual_qty,
         MOD(ABS(HASH(r.d, 'p104fc')), 100) AS h
  FROM raw r CROSS JOIN balance b
)
SELECT
  'P104', 'P01',
  DATEADD(day, -f.d, a.A)                                                      AS DEMAND_DATE,
  GREATEST(0, ROUND(f.actual_qty * (0.93 + MOD(f.h, 15) / 100.0)))             AS FORECAST_QTY,
  f.actual_qty                                                                 AS ACTUAL_DEMAND_QTY,
  'FY' || YEAR(DATEADD(day, -f.d, a.A))::VARCHAR
        || '-M' || LPAD(MONTH(DATEADD(day, -f.d, a.A))::VARCHAR, 2, '0')
        || '-V' || (1 + MOD(f.h, 3))::VARCHAR                                  AS FORECAST_VERSION,
  GET(ARRAY_CONSTRUCT('Statistical Forecast','Sales Input','ML Model','Customer Commit'),
      MOD(f.h, 4))::VARCHAR                                                    AS DEMAND_SOURCE,
  'Stable'                                                                     AS DEMAND_PATTERN
FROM final f CROSS JOIN anchor a;

/* ===========================================================================
   SECTION 15a : CRM_ORDERS.CUSTOMER_ORDER_LINES - bulk (~52,000 lines /
                 21,000 orders). Fulfilled / partially fulfilled / open /
                 cancelled / overdue mix. Priority driven by customer segment.
   EXCLUSION: no other OPEN P104 @ P01 line due within anchor..anchor+14, so
   the flagship shortage stays deterministic.
   =========================================================================== */
TRUNCATE TABLE CRM_ORDERS.CUSTOMER_ORDER_LINES;
INSERT INTO CRM_ORDERS.CUSTOMER_ORDER_LINES
  (ORDER_ID, ORDER_LINE, CUSTOMER_ID, PART_NUMBER, FULFILLMENT_SITE, ORDER_DATE,
   REQUESTED_DATE, DUE_DATE, ORDERED_QTY, FULFILLED_QTY, UNIT_SELL_PRICE,
   ORDER_VALUE, ORDER_STATUS, PRIORITY)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
ords AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS o
  FROM TABLE(GENERATOR(ROWCOUNT => 21000))
),
lines AS (
  SELECT o.o, f.value::NUMBER AS line_no
  FROM ords o,
       LATERAL FLATTEN(input => ARRAY_GENERATE_RANGE(1, 2 + MOD(ABS(HASH(o.o, 'CL')), 4))) f
),
cov AS (
  SELECT ROW_NUMBER() OVER (ORDER BY MATERIAL_NO, PLANT_CODE) AS rn, MATERIAL_NO, PLANT_CODE
  FROM PUBLIC.PART_SITE_COVERAGE
),
picked AS (
  SELECT l.o, l.line_no, c.MATERIAL_NO, c.PLANT_CODE,
         'C' || LPAD((1 + MOD(ABS(HASH(l.o, 'cust')), 500))::VARCHAR, 4, '0') AS CUSTOMER_ID,
         MOD(ABS(HASH(l.o, l.line_no, 'h')), 100)  AS h,
         MOD(ABS(HASH(l.o, l.line_no, 'st')), 100) AS bucket,
         a.A
  FROM lines l
  JOIN cov c ON c.rn = 1 + MOD(ABS(HASH(l.o, l.line_no, 'ccmb')), 2000)
  CROSS JOIN anchor a
),
dated AS (
  SELECT p.*,
         DATEADD(day, -MOD(ABS(HASH(p.o, 'cod')), 400), p.A) AS order_date
  FROM picked p
),
dated2 AS (
  SELECT d.*,
         DATEADD(day, 7 + MOD(ABS(HASH(d.o, d.line_no, 'rq')), 40), d.order_date) AS requested_date
  FROM dated d
),
dated3 AS (
  SELECT d.*,
         DATEADD(day, MOD(ABS(HASH(d.o, d.line_no, 'du')), 5) - 2, d.requested_date) AS due_date,
         10 + MOD(ABS(HASH(d.o, d.line_no, 'qy')), 590) AS ordered_qty
  FROM dated2 d
),
statused AS (
  SELECT d.*,
         CASE WHEN d.bucket < 4 THEN 'CANCELLED'
              WHEN d.due_date < d.A THEN
                   CASE WHEN d.bucket < 74 THEN 'FULFILLED'
                        WHEN d.bucket < 88 THEN 'PARTIALLY_FULFILLED'
                        ELSE 'OVERDUE' END
              ELSE 'OPEN' END AS order_status
  FROM dated3 d
)
SELECT
  'CO' || LPAD(s.o::VARCHAR, 6, '0')                                           AS ORDER_ID,
  s.line_no                                                                    AS ORDER_LINE,
  s.CUSTOMER_ID,
  s.MATERIAL_NO                                                                AS PART_NUMBER,
  s.PLANT_CODE                                                                 AS FULFILLMENT_SITE,
  s.order_date,
  s.requested_date,
  s.due_date,
  s.ordered_qty,
  CASE s.order_status
    WHEN 'FULFILLED'           THEN s.ordered_qty
    WHEN 'PARTIALLY_FULFILLED' THEN ROUND(s.ordered_qty * (0.40 + MOD(s.h, 45) / 100.0))
    WHEN 'OVERDUE'             THEN ROUND(s.ordered_qty * (MOD(s.h, 30) / 100.0))
    ELSE 0
  END                                                                          AS FULFILLED_QTY,
  ROUND(mm.STANDARD_COST * (1.32 + MOD(s.h, 30) / 100.0), 2)                    AS UNIT_SELL_PRICE,
  ROUND(s.ordered_qty * ROUND(mm.STANDARD_COST * (1.32 + MOD(s.h, 30) / 100.0), 2), 2) AS ORDER_VALUE,
  s.order_status                                                               AS ORDER_STATUS,
  CASE cm.CUSTOMER_SEGMENT
    WHEN 'Strategic'  THEN IFF(MOD(s.h, 2) = 0, 'CRITICAL', 'HIGH')
    WHEN 'Enterprise' THEN IFF(MOD(s.h, 2) = 0, 'HIGH', 'MEDIUM')
    WHEN 'Mid-Market' THEN IFF(MOD(s.h, 3) = 0, 'MEDIUM', 'LOW')
    ELSE 'LOW'
  END                                                                          AS PRIORITY
FROM statused s
JOIN SAP_ERP.MATERIAL_MASTER mm ON mm.MATERIAL_NO = s.MATERIAL_NO
JOIN CRM_ORDERS.CUSTOMER_MASTER cm ON cm.CUSTOMER_ID = s.CUSTOMER_ID
WHERE NOT (s.MATERIAL_NO = 'P104' AND s.PLANT_CODE = 'P01'
           AND s.due_date BETWEEN s.A AND DATEADD(day, 14, s.A));

/* ===========================================================================
   SECTION 16 : SUPPLIER_PORTAL.SUPPLIER_SCORECARDS (100 suppliers x 12 months)
   Named profiles:
     S017 - weak delivery, high lead-time variability (flagship risk supplier)
     S042 - strong all round (flagship alternate supplier)
     S011 - high performer
     S055 - deteriorating over time
     S073 - poor QUALITY but good delivery (multidimensional risk)
     S088 - repeatedly poor delivery
   RISK_CATEGORY is derived uniformly from the underlying scores, so risk is
   genuinely multidimensional rather than delivery-only.
   =========================================================================== */
TRUNCATE TABLE SUPPLIER_PORTAL.SUPPLIER_SCORECARDS;
INSERT INTO SUPPLIER_PORTAL.SUPPLIER_SCORECARDS
  (SUPPLIER_ID, SCORECARD_DATE, QUALITY_SCORE, REJECTION_RATE,
   REPORTED_LEAD_TIME_DAYS, LEAD_TIME_VARIABILITY, SERVICE_SCORE,
   RISK_CATEGORY, OPEN_ISSUE_COUNT)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
months AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS m
  FROM TABLE(GENERATOR(ROWCOUNT => 12))
),
grid AS (
  SELECT v.VENDOR_ID AS sid, TO_NUMBER(SUBSTR(v.VENDOR_ID, 2)) AS n, mo.m,
         LAST_DAY(DATEADD(month, -(mo.m + 1), a.A)) AS sc_date,
         MOD(ABS(HASH(v.VENDOR_ID, mo.m, 'sc')), 100) AS h
  FROM SAP_ERP.VENDOR_MASTER v
  CROSS JOIN months mo
  CROSS JOIN anchor a
),
scored AS (
  SELECT g.*,
    CASE WHEN g.n = 17 THEN 87.0 + MOD(g.h, 4)
         WHEN g.n = 42 THEN 97.0 + MOD(g.m, 2)
         WHEN g.n = 11 THEN 96.0 + MOD(g.m, 2)
         WHEN g.n = 55 THEN 90.0 - (11 - g.m) * 0.4
         WHEN g.n = 73 THEN 78.0 + MOD(g.m, 3)
         WHEN g.n = 88 THEN 92.0 + MOD(g.h, 3)
         ELSE 84.0 + MOD(g.h, 15) END AS quality_score,
    CASE WHEN g.n = 17 THEN ROUND(0.0310 + g.m * 0.0002, 4)
         WHEN g.n = 42 THEN 0.0040
         WHEN g.n = 11 THEN 0.0055
         WHEN g.n = 55 THEN ROUND(0.0180 + (11 - g.m) * 0.0009, 4)
         WHEN g.n = 73 THEN 0.0650
         WHEN g.n = 88 THEN 0.0210
         ELSE ROUND(0.0040 + MOD(g.h, 26) / 1000.0, 4) END AS rejection_rate,
    CASE WHEN g.n = 17 THEN 28.0 + MOD(g.m, 4)
         WHEN g.n = 42 THEN  7.0 + MOD(g.m, 2)
         WHEN g.n = 11 THEN  9.0 + MOD(g.m, 2)
         WHEN g.n = 55 THEN 16.0 + (11 - g.m) * 0.5
         WHEN g.n = 73 THEN 14.0 + MOD(g.m, 2)
         WHEN g.n = 88 THEN 32.0 + MOD(g.m, 5)
         ELSE 10.0 + MOD(g.h, 30) END AS reported_lead_time,
    CASE WHEN g.n = 17 THEN ROUND(7.5 + MOD(g.m, 4) * 0.6, 2)
         WHEN g.n = 42 THEN ROUND(1.0 + MOD(g.m, 2) * 0.3, 2)
         WHEN g.n = 11 THEN ROUND(1.2 + MOD(g.m, 2) * 0.2, 2)
         WHEN g.n = 55 THEN ROUND(2.0 + (11 - g.m) * 0.5, 2)
         WHEN g.n = 73 THEN 1.80
         WHEN g.n = 88 THEN ROUND(6.5 + MOD(g.m, 3) * 0.4, 2)
         ELSE ROUND(1.0 + MOD(g.h, 50) / 10.0, 2) END AS lead_time_variability,
    CASE WHEN g.n = 17 THEN 63.0 + MOD(g.m, 6)
         WHEN g.n = 42 THEN 93.0 + MOD(g.m, 4)
         WHEN g.n = 11 THEN 95.0 + MOD(g.m, 3)
         WHEN g.n = 55 THEN 92.0 - (11 - g.m) * 2.5
         WHEN g.n = 73 THEN 94.0 + MOD(g.m, 2)
         WHEN g.n = 88 THEN 68.0 + MOD(g.m, 4)
         ELSE 74.0 + MOD(g.h, 24) END AS service_score,
    CASE WHEN g.n = 17 THEN 4 + MOD(g.m, 6)
         WHEN g.n = 42 THEN MOD(g.m, 2)
         WHEN g.n = 11 THEN MOD(g.m, 2)
         WHEN g.n = 55 THEN 1 + FLOOR((11 - g.m) / 2)
         WHEN g.n = 73 THEN 3 + MOD(g.m, 3)
         WHEN g.n = 88 THEN 5 + MOD(g.m, 4)
         ELSE MOD(g.h, 7) END AS open_issues
  FROM grid g
)
SELECT
  s.sid, s.sc_date,
  ROUND(s.quality_score, 2), s.rejection_rate,
  ROUND(s.reported_lead_time, 2), s.lead_time_variability,
  ROUND(s.service_score, 2),
  CASE WHEN (s.service_score < 66 AND s.lead_time_variability > 7.0) OR s.rejection_rate > 0.080
            THEN 'Critical'
       WHEN s.service_score < 74 OR s.lead_time_variability > 5.5
            OR s.rejection_rate > 0.050 OR s.quality_score < 82
            THEN 'High'
       WHEN s.service_score < 84 OR s.lead_time_variability > 3.0
            OR s.rejection_rate > 0.025
            THEN 'Medium'
       ELSE 'Low' END,
  s.open_issues
FROM scored s;

/* ===========================================================================
   SECTION 17a : DOCUMENTS.SUPPLIER_DOCUMENTS - templated supplier documents
   100 Supplier Contracts + 20 SLAs + 10 Scorecard Narratives +
   4 Quality Agreements = 134 supplier-specific documents.
   Deterministic SQL text construction only - no per-document LLM calls.
   =========================================================================== */
TRUNCATE TABLE DOCUMENTS.SUPPLIER_DOCUMENTS;
INSERT INTO DOCUMENTS.SUPPLIER_DOCUMENTS
  (DOCUMENT_ID, SUPPLIER_ID, DOCUMENT_TYPE, TITLE, EFFECTIVE_DATE, EXPIRY_DATE,
   CONTENT, SOURCE_REFERENCE, CREATED_AT)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
sup AS (
  SELECT v.VENDOR_ID, v.VENDOR_NAME, v.COUNTRY, v.REGION, v.VENDOR_TIER,
         v.DEFAULT_CURRENCY, v.PAYMENT_TERMS,
         TO_NUMBER(SUBSTR(v.VENDOR_ID, 2)) AS n,
         CASE v.VENDOR_TIER WHEN 'Strategic' THEN 97 WHEN 'Preferred' THEN 95
                            WHEN 'Standard' THEN 92 ELSE 90 END AS otd_target,
         CASE v.VENDOR_TIER WHEN 'Strategic' THEN 99.0 WHEN 'Preferred' THEN 98.5
                            WHEN 'Standard' THEN 97.5 ELSE 96.0 END AS quality_target,
         COALESCE((SELECT ROUND(AVG(sm.CONTRACT_LEAD_TIME_DAYS))
                   FROM SAP_ERP.SUPPLIER_MATERIAL sm
                   WHERE sm.VENDOR_ID = v.VENDOR_ID), 21) AS committed_lead_time
  FROM SAP_ERP.VENDOR_MASTER v
),
docs AS (
  /* ---- 100 supplier contracts ---- */
  /* NOTE: do NOT also project s.VENDOR_ID explicitly - s.* already carries it,
     and duplicating it makes d.VENDOR_ID ambiguous in the outer SELECT. */
  SELECT s.n AS ord, 0 AS grp, 'Supplier Contract' AS dtype,
         'Master Supply Agreement - ' || s.VENDOR_NAME || ' (' || s.VENDOR_ID || ')' AS title,
         s.*
  FROM sup s
  UNION ALL
  /* ---- 20 SLAs (includes S017) ---- */
  SELECT s.n, 1, 'SLA',
         'Service Level Agreement - ' || s.VENDOR_NAME || ' (' || s.VENDOR_ID || ')',
         s.*
  FROM sup s WHERE MOD(s.n, 5) = 2
  UNION ALL
  /* ---- 10 scorecard narratives ---- */
  SELECT s.n, 2, 'Supplier Scorecard Narrative',
         'Quarterly Supplier Performance Review - ' || s.VENDOR_NAME,
         s.*
  FROM sup s WHERE s.n IN (11, 17, 23, 42, 55, 64, 73, 81, 88, 96)
  UNION ALL
  /* ---- 4 quality agreements ---- */
  SELECT s.n, 3, 'Quality Agreement',
         'Quality Assurance Agreement - ' || s.VENDOR_NAME,
         s.*
  FROM sup s WHERE s.n IN (17, 42, 73, 88)
)
SELECT
  'DOC' || LPAD((d.grp * 200 + d.ord)::VARCHAR, 6, '0')                        AS DOCUMENT_ID,
  d.VENDOR_ID                                                                  AS SUPPLIER_ID,
  d.dtype                                                                      AS DOCUMENT_TYPE,
  d.title                                                                      AS TITLE,
  DATEADD(day, -(200 + MOD(d.n * 7, 500)), a.A)                                AS EFFECTIVE_DATE,
  DATEADD(day,  (200 + MOD(d.n * 11, 500)), a.A)                               AS EXPIRY_DATE,
  CASE d.dtype

    WHEN 'Supplier Contract' THEN
      '1. PARTIES AND SCOPE' || CHR(10) ||
      'This Master Supply Agreement is entered into between the Buyer and ' || d.VENDOR_NAME ||
      ' (supplier reference ' || d.VENDOR_ID || '), registered in ' || d.COUNTRY ||
      ', hereinafter the Supplier. The Supplier is classified as a ' || d.VENDOR_TIER ||
      ' source within the Buyer supplier segmentation framework and is approved to supply the material' ||
      ' portfolio recorded in the Buyer sourcing master.' || CHR(10) || CHR(10) ||
      '2. DELIVERY PERFORMANCE COMMITMENT' || CHR(10) ||
      'The Supplier shall maintain a rolling on-time delivery (OTD) performance of not less than ' ||
      d.otd_target::VARCHAR || ' percent, measured monthly against the confirmed promised delivery date' ||
      ' recorded on each purchase order line. Deliveries received after the promised date are counted as' ||
      ' late irrespective of cause, save for events of force majeure notified under clause 8.' || CHR(10) || CHR(10) ||
      '3. LEAD TIME COMMITMENT' || CHR(10) ||
      'The committed order-to-delivery lead time for the Supplier material portfolio is ' ||
      d.committed_lead_time::VARCHAR || ' calendar days from purchase order confirmation. The Supplier shall' ||
      ' confirm each purchase order within two (2) business days of receipt and shall notify the Buyer of any' ||
      ' anticipated deviation from the committed lead time within seventy-two (72) hours of becoming aware of it.' || CHR(10) || CHR(10) ||
      '4. QUALITY THRESHOLD' || CHR(10) ||
      'The Supplier shall maintain an incoming quality acceptance rate of not less than ' ||
      d.quality_target::VARCHAR || ' percent. Lots exceeding the agreed rejection threshold shall be subject to' ||
      ' containment, root-cause analysis and a corrective action plan submitted within ten (10) working days.' || CHR(10) || CHR(10) ||
      '5. EXPEDITED DELIVERY PROVISIONS' || CHR(10) ||
      'Where the Buyer requires accelerated delivery to protect customer commitments, the Supplier shall' ||
      ' cooperate in arranging expedited transport. Where the delay giving rise to the expedite request is' ||
      ' attributable to the Supplier, the incremental freight differential shall be borne by the Supplier.' ||
      ' Where the request arises from a Buyer-side demand change, the differential shall be borne by the Buyer.' || CHR(10) || CHR(10) ||
      '6. PENALTY AND REMEDY' || CHR(10) ||
      'Sustained failure to meet the OTD commitment in two consecutive measurement months entitles the Buyer' ||
      ' to apply a service credit of one point five (1.5) percent of the affected purchase order line value per' ||
      ' commenced week of delay, and to re-allocate volume to an approved alternate source without penalty.' || CHR(10) || CHR(10) ||
      '7. ESCALATION' || CHR(10) ||
      'Delivery exceptions shall be escalated to the Supplier account owner within twenty-four (24) hours and' ||
      ' to the joint Supply Continuity Review within five (5) working days where the exception affects a part' ||
      ' classified as Critical or High criticality.' || CHR(10) || CHR(10) ||
      '8. CONTINUITY OBLIGATIONS' || CHR(10) ||
      'For parts classified as Critical, the Supplier shall hold finished-goods safety stock equivalent to no' ||
      ' less than ten (10) days of the rolling agreed weekly call-off, and shall maintain a documented' ||
      ' business continuity plan covering single-site and single-tooling exposures.' || CHR(10) || CHR(10) ||
      '9. COMMERCIAL TERMS' || CHR(10) ||
      'Prices are denominated in ' || d.DEFAULT_CURRENCY || ' and payment terms are ' || d.PAYMENT_TERMS ||
      '. Agreed unit prices, minimum order quantities and maximum weekly supply quantities are recorded in the' ||
      ' Buyer sourcing master and form part of this Agreement.'

    WHEN 'SLA' THEN
      CASE WHEN d.VENDOR_ID = 'S017' THEN
        'SERVICE LEVEL AGREEMENT - SUPPLIER S017 (' || d.VENDOR_NAME || ')' || CHR(10) ||
        'Status: ACTIVE. Applies to all hydraulic control valve assemblies supplied to Buyer plants, including' ||
        ' part P104 delivered to plant P01.' || CHR(10) || CHR(10) ||
        '1. COMMITTED LEAD TIME' || CHR(10) ||
        'The committed order-to-delivery lead time for part P104 is twenty-eight (28) calendar days from purchase' ||
        ' order confirmation, comprising seven (7) days production and twenty-one (21) days ocean transit to plant' ||
        ' P01. Any change of transport mode requires prior written agreement from Buyer logistics.' || CHR(10) || CHR(10) ||
        '2. REQUIRED DELIVERY PERFORMANCE' || CHR(10) ||
        'The Supplier shall achieve a minimum rolling on-time delivery performance of ninety-five (95) percent' ||
        ' measured against the promised delivery date. Lead-time variability shall not exceed three (3) days' ||
        ' standard deviation on a rolling three-month basis. The Supplier acknowledges that P104 is classified' ||
        ' as a Critical part and that late delivery has direct customer-service consequences.' || CHR(10) || CHR(10) ||
        '3. DELAY NOTIFICATION AND ESCALATION OBLIGATIONS' || CHR(10) ||
        'The Supplier shall notify the Buyer within twenty-four (24) hours of becoming aware of any event likely' ||
        ' to delay a confirmed shipment, stating the revised projected delivery date and the root cause. Delays' ||
        ' exceeding three (3) days on a Critical part shall be escalated the same working day to the Buyer' ||
        ' Category Manager and, where the projected delay exceeds five (5) days, to the joint Supply Continuity' ||
        ' Council which shall convene within forty-eight (48) hours to agree a recovery plan.' || CHR(10) || CHR(10) ||
        '4. EXPEDITE TERMS' || CHR(10) ||
        'Where a confirmed shipment is projected to arrive later than the promised delivery date, the Buyer may' ||
        ' instruct conversion of the affected quantity to air freight. The approved expedited air lane to plant' ||
        ' P01 has a transit time of four (4) days. The expedited freight rate is applied at a factor of 2.6' ||
        ' times the standard ocean rate for the lane. Where the delay is attributable to the Supplier, the' ||
        ' Supplier shall bear fifty (50) percent of the incremental freight differential; where the delay is' ||
        ' attributable to the carrier and the Supplier has met its notification obligations, the differential' ||
        ' shall be shared equally between the parties.' || CHR(10) || CHR(10) ||
        '5. PENALTY CLAUSE' || CHR(10) ||
        'A service credit of two (2) percent of the delayed purchase order line value shall apply for each' ||
        ' commenced week of delay beyond the promised delivery date on Critical parts, capped at ten (10)' ||
        ' percent of the affected line value.' || CHR(10) || CHR(10) ||
        '6. SUPPLY CONTINUITY AND SAFETY STOCK' || CHR(10) ||
        'The Supplier shall hold finished-goods safety stock of not less than ten (10) days of the agreed weekly' ||
        ' call-off for part P104. The Buyer reserves the right to activate an approved alternate source, to' ||
        ' execute an interplant stock transfer, or to expedite in-transit material where projected supply' ||
        ' timing places customer commitments at risk, without prejudice to its remedies under this Agreement.' || CHR(10) || CHR(10) ||
        '7. QUALITY THRESHOLD' || CHR(10) ||
        'Incoming acceptance shall be not less than ninety-eight (98) percent. The current rolling rejection' ||
        ' rate is under formal review following sustained deterioration in delivery reliability.'
      WHEN d.VENDOR_ID = 'S042' THEN
        'SERVICE LEVEL AGREEMENT - SUPPLIER S042 (' || d.VENDOR_NAME || ')' || CHR(10) ||
        'Status: ACTIVE. Approved alternate source, including part P104 for plant P01.' || CHR(10) || CHR(10) ||
        '1. COMMITTED LEAD TIME' || CHR(10) ||
        'The committed order-to-delivery lead time for part P104 is seven (7) calendar days from purchase order' ||
        ' confirmation for quantities up to the agreed maximum weekly supply quantity of four thousand five' ||
        ' hundred (4,500) units. The Supplier operates from ' || d.COUNTRY || ', permitting road delivery to' ||
        ' plant P01 without ocean transit exposure.' || CHR(10) || CHR(10) ||
        '2. REQUIRED DELIVERY PERFORMANCE' || CHR(10) ||
        'The Supplier shall maintain rolling on-time delivery of not less than ninety-seven (97) percent and' ||
        ' lead-time variability not exceeding one point five (1.5) days standard deviation.' || CHR(10) || CHR(10) ||
        '3. SURGE AND SUBSTITUTION PROVISIONS' || CHR(10) ||
        'The Supplier shall accept surge call-off up to the agreed maximum weekly supply quantity with five (5)' ||
        ' working days notice, for use where the primary source is unable to meet a confirmed requirement.' ||
        ' Surge volumes are invoiced at the agreed alternate-source unit price, which is above the primary' ||
        ' source price. The price differential is accepted by the Buyer as the cost of supply assurance.' || CHR(10) || CHR(10) ||
        '4. ESCALATION AND QUALITY' || CHR(10) ||
        'Delivery exceptions shall be notified within twenty-four (24) hours. Incoming acceptance shall be not' ||
        ' less than ninety-nine (99) percent. The Supplier holds an unqualified quality approval for part P104.'
      ELSE
        'SERVICE LEVEL AGREEMENT - ' || d.VENDOR_NAME || ' (' || d.VENDOR_ID || ')' || CHR(10) || CHR(10) ||
        '1. SERVICE COMMITMENTS' || CHR(10) ||
        'The Supplier shall maintain rolling on-time delivery of not less than ' || d.otd_target::VARCHAR ||
        ' percent against the promised delivery date and shall confirm purchase orders within two (2) business' ||
        ' days.' || CHR(10) || CHR(10) ||
        '2. LEAD TIME' || CHR(10) ||
        'The committed lead time is ' || d.committed_lead_time::VARCHAR || ' calendar days from order' ||
        ' confirmation. Lead-time variability shall not exceed three (3) days standard deviation.' || CHR(10) || CHR(10) ||
        '3. QUALITY' || CHR(10) ||
        'Incoming acceptance shall be not less than ' || d.quality_target::VARCHAR || ' percent, with corrective' ||
        ' action plans submitted within ten (10) working days of any threshold breach.' || CHR(10) || CHR(10) ||
        '4. EXPEDITE AND ESCALATION' || CHR(10) ||
        'Where accelerated delivery is required, the Supplier shall cooperate in arranging expedited transport at' ||
        ' the applicable lane expedite factor. Delivery exceptions shall be escalated within twenty-four (24)' ||
        ' hours and, for Critical parts, to the joint Supply Continuity Review within five (5) working days.' || CHR(10) || CHR(10) ||
        '5. PENALTY' || CHR(10) ||
        'A service credit of one point five (1.5) percent of the affected line value per commenced week of delay' ||
        ' applies where the delay is attributable to the Supplier.'
      END

    WHEN 'Supplier Scorecard Narrative' THEN
      'QUARTERLY SUPPLIER PERFORMANCE REVIEW - ' || d.VENDOR_NAME || ' (' || d.VENDOR_ID || ')' || CHR(10) || CHR(10) ||
      '1. SUMMARY' || CHR(10) ||
      'This narrative accompanies the monthly scorecard series recorded in the supplier portal for ' ||
      d.VENDOR_ID || ', a ' || d.VENDOR_TIER || ' source based in ' || d.COUNTRY || ' (' || d.REGION ||
      '). The review covers delivery reliability, lead-time stability, incoming quality and issue closure.' || CHR(10) || CHR(10) ||
      '2. DELIVERY AND LEAD TIME' || CHR(10) ||
      'The contractual OTD target for this supplier is ' || d.otd_target::VARCHAR || ' percent against a' ||
      ' committed lead time of ' || d.committed_lead_time::VARCHAR || ' days. Reviewers should read the' ||
      ' reported lead time together with lead-time variability: a stable long lead time is materially' ||
      ' different in planning terms from a short but highly variable one, and buffer policy is set from the' ||
      ' variability rather than the mean.' || CHR(10) || CHR(10) ||
      '3. QUALITY' || CHR(10) ||
      'The quality acceptance threshold is ' || d.quality_target::VARCHAR || ' percent. Delivery performance and' ||
      ' quality performance are assessed independently; a supplier may hold acceptable delivery reliability' ||
      ' while presenting elevated rejection exposure, and the composite risk view must reflect both.' || CHR(10) || CHR(10) ||
      '4. ACTIONS' || CHR(10) ||
      'Open issues are tracked to closure in the supplier portal. Where the composite risk view remains' ||
      ' elevated across two consecutive reviews, category management shall qualify or activate an approved' ||
      ' alternate source for the affected Critical and High criticality parts.'

    ELSE
      'QUALITY ASSURANCE AGREEMENT - ' || d.VENDOR_NAME || ' (' || d.VENDOR_ID || ')' || CHR(10) || CHR(10) ||
      '1. SCOPE' || CHR(10) ||
      'This Quality Assurance Agreement supplements the Master Supply Agreement with ' || d.VENDOR_ID ||
      ' and governs incoming inspection, rejection handling and corrective action.' || CHR(10) || CHR(10) ||
      '2. ACCEPTANCE THRESHOLD' || CHR(10) ||
      'The Supplier shall maintain an incoming acceptance rate of not less than ' || d.quality_target::VARCHAR ||
      ' percent. The rolling rejection rate recorded in the supplier portal is the governing measure.' || CHR(10) || CHR(10) ||
      '3. CONTAINMENT AND CORRECTIVE ACTION' || CHR(10) ||
      'On breach of the acceptance threshold the Supplier shall implement containment within twenty-four (24)' ||
      ' hours, submit an interim root-cause statement within three (3) working days and a full corrective' ||
      ' action plan within ten (10) working days.' || CHR(10) || CHR(10) ||
      '4. RELATIONSHIP TO DELIVERY PERFORMANCE' || CHR(10) ||
      'Quality performance is assessed independently of delivery performance. Acceptable delivery reliability' ||
      ' does not discharge the Supplier from the acceptance threshold obligations in this Agreement.' || CHR(10) || CHR(10) ||
      '5. ESCALATION' || CHR(10) ||
      'Repeat breaches within any rolling six-month period shall be escalated to the Buyer Quality Council and' ||
      ' may result in suspension of new order placement pending requalification.'
  END                                                                          AS CONTENT,
  'supplier-portal://' || d.VENDOR_ID || '/' || REPLACE(LOWER(d.dtype), ' ', '-') || '/v1' AS SOURCE_REFERENCE,
  TO_TIMESTAMP_LTZ(DATEADD(day, -(200 + MOD(d.n * 7, 500)), a.A))              AS CREATED_AT
FROM docs d CROSS JOIN anchor a;

/* ===========================================================================
   SECTION 17b : DOCUMENTS.SUPPLIER_DOCUMENTS - company-wide policies
   SUPPLIER_ID is NULL here (controlled optional-NULL example).
   =========================================================================== */
INSERT INTO DOCUMENTS.SUPPLIER_DOCUMENTS
  (DOCUMENT_ID, SUPPLIER_ID, DOCUMENT_TYPE, TITLE, EFFECTIVE_DATE, EXPIRY_DATE,
   CONTENT, SOURCE_REFERENCE, CREATED_AT)
WITH anchor AS (
  SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1
),
p AS (
  SELECT 1 AS k, 'Procurement Policy' AS dtype,
         'Global Procurement Policy - Supplier Performance and Sourcing' AS title,
         'GLOBAL PROCUREMENT POLICY - SUPPLIER PERFORMANCE AND SOURCING' || CHR(10) || CHR(10) ||
         '1. PURPOSE' || CHR(10) ||
         'This policy defines how supplier delivery performance, lead-time reliability and quality are measured' ||
         ' and how sourcing decisions respond to measured risk.' || CHR(10) || CHR(10) ||
         '2. ON-TIME DELIVERY MEASUREMENT' || CHR(10) ||
         'On-time delivery is measured at delivery-line level against the promised delivery date recorded on the' ||
         ' purchase order line. Cancelled purchase order lines are excluded from the measurement population.' ||
         ' Partial deliveries are counted against the line only when the full confirmed quantity has been' ||
         ' received.' || CHR(10) || CHR(10) ||
         '3. DUAL SOURCING' || CHR(10) ||
         'Every part classified as Critical shall have at least one approved alternate source qualified and' ||
         ' maintained in the sourcing master, with a recorded maximum weekly supply quantity sufficient to' ||
         ' cover a material share of normal call-off.' || CHR(10) || CHR(10) ||
         '4. PRICE VERSUS ASSURANCE' || CHR(10) ||
         'An approved alternate source may carry a higher unit price than the primary source. Where activation' ||
         ' of an alternate source avoids a customer-service failure on a Critical part, the price differential' ||
         ' is an accepted cost of supply assurance and does not require exception approval below the threshold' ||
         ' set by the Category Council.' || CHR(10) || CHR(10) ||
         '5. ESCALATION' || CHR(10) ||
         'Projected supply shortfalls affecting confirmed customer commitments within a fourteen (14) day' ||
         ' horizon shall be escalated to the Supply Continuity Council, which shall evaluate expedite,' ||
         ' interplant transfer and alternate-source options on a comparable cost and timing basis.' AS content
  UNION ALL
  SELECT 2, 'Procurement Policy',
         'Supplier Risk Classification Standard',
         'SUPPLIER RISK CLASSIFICATION STANDARD' || CHR(10) || CHR(10) ||
         '1. SCOPE' || CHR(10) ||
         'This standard defines the inputs to the composite supplier risk view used in category reviews.' || CHR(10) || CHR(10) ||
         '2. INPUTS' || CHR(10) ||
         'The composite view shall consider, as independent dimensions: on-time delivery performance,' ||
         ' lead-time variability, incoming quality score, rejection rate, service score and open order' ||
         ' exposure. No single dimension shall determine the classification on its own.' || CHR(10) || CHR(10) ||
         '3. INTERPRETATION' || CHR(10) ||
         'A supplier with strong delivery reliability but elevated rejection exposure presents quality risk and' ||
         ' shall not be classified Low. A supplier with acceptable quality but high lead-time variability' ||
         ' presents delivery risk and requires increased buffer cover.' || CHR(10) || CHR(10) ||
         '4. REVIEW CADENCE' || CHR(10) ||
         'Classification is reviewed monthly against the portal scorecard series and at any point where a' ||
         ' Critical part is affected by a projected delay exceeding three (3) days.'
  UNION ALL
  SELECT 3, 'Procurement Policy',
         'Purchase Order Cancellation and Exclusion Standard',
         'PURCHASE ORDER CANCELLATION AND EXCLUSION STANDARD' || CHR(10) || CHR(10) ||
         '1. PURPOSE' || CHR(10) ||
         'To ensure consistent treatment of cancelled and amended purchase order lines in performance' ||
         ' reporting.' || CHR(10) || CHR(10) ||
         '2. RULE' || CHR(10) ||
         'Purchase order lines carrying status CANCELLED are excluded from delivery-performance populations,' ||
         ' from lead-time calculations and from landed-cost aggregation. They remain in the transactional' ||
         ' record for audit purposes and shall not be deleted.' || CHR(10) || CHR(10) ||
         '3. PARTIAL DELIVERY' || CHR(10) ||
         'Lines carrying status PARTIALLY_DELIVERED remain in the population. The received quantity and the' ||
         ' confirmed order quantity shall both be retained so that fill performance can be computed without' ||
         ' reference to a precomputed ratio.'
  UNION ALL
  SELECT 4, 'Logistics Policy',
         'Global Logistics Policy - Expedite and Mode Selection',
         'GLOBAL LOGISTICS POLICY - EXPEDITE AND MODE SELECTION' || CHR(10) || CHR(10) ||
         '1. MODE SELECTION' || CHR(10) ||
         'Standard mode selection follows the approved lane catalogue. Ocean is the default mode for' ||
         ' intercontinental and long-haul intra-regional inbound flows; road is the default for domestic' ||
         ' inbound and for interplant transfer.' || CHR(10) || CHR(10) ||
         '2. EXPEDITE AUTHORISATION' || CHR(10) ||
         'Conversion of a confirmed shipment to an expedited lane requires that the projected delivery date' ||
         ' exceeds the promised delivery date and that a customer commitment is at risk. The incremental cost' ||
         ' is computed as the lane expedite cost factor applied to the standard lane cost.' || CHR(10) || CHR(10) ||
         '3. LANDED COST' || CHR(10) ||
         'Landed cost comprises the purchase value of the delivered quantity plus freight, duties, handling and' ||
         ' any other logistics charges recorded against the shipment line. All four cost components shall be' ||
         ' captured separately at shipment-line level and shall not be netted.' || CHR(10) || CHR(10) ||
         '4. INTERPLANT TRANSFER' || CHR(10) ||
         'An interplant transfer may be authorised only where the originating plant retains inventory at or' ||
         ' above its own safety stock level after the transfer, and where the lane transit time permits arrival' ||
         ' before the affected customer commitment falls due.'
  UNION ALL
  SELECT 5, 'Logistics Policy',
         'Inventory and Safety Stock Policy',
         'INVENTORY AND SAFETY STOCK POLICY' || CHR(10) || CHR(10) ||
         '1. SAFETY STOCK' || CHR(10) ||
         'Safety stock is held to absorb demand and supply variability and is not available for the routine' ||
         ' fulfilment of confirmed customer orders. Usable inventory for planning purposes is the available' ||
         ' quantity less the safety stock quantity at the same site.' || CHR(10) || CHR(10) ||
         '2. DAYS OF INVENTORY' || CHR(10) ||
         'Days of inventory is expressed as available inventory divided by the governed average daily demand' ||
         ' for the part and location. The averaging window shall be stated whenever the measure is reported.' || CHR(10) || CHR(10) ||
         '3. STOCKOUT RISK' || CHR(10) ||
         'Stockout risk assessment shall consider current inventory, safety stock, confirmed demand in the' ||
         ' horizon, inbound supply quantity and the projected rather than the originally expected arrival date' ||
         ' of that inbound supply.' || CHR(10) || CHR(10) ||
         '4. SNAPSHOT INTEGRITY' || CHR(10) ||
         'Inventory positions are recorded as dated snapshots. Analysis of a current position shall use the' ||
         ' latest snapshot date available for the site and part.'
)
SELECT
  'DOC' || LPAD((900 + p.k)::VARCHAR, 6, '0'),
  NULL,
  p.dtype,
  p.title,
  DATEADD(day, -(300 + p.k * 10), a.A),
  DATEADD(day,  (400 + p.k * 10), a.A),
  p.content,
  'policy-repository://global/' || p.k::VARCHAR || '/v1',
  TO_TIMESTAMP_LTZ(DATEADD(day, -(300 + p.k * 10), a.A))
FROM p CROSS JOIN anchor a;

/* ===========================================================================
   SECTION 18 : FLAGSHIP SCENARIO - S017 / P104 / P01
   ---------------------------------------------------------------------------
   18a  Purchase order PO900001 : S017 -> P104 -> P01, promised anchor+10
   18b  Shipment SH900001       : in transit, expected anchor+10,
                                  projected anchor+15  (5-day delay)
   18c  Latest inventory        : P104@P01 8,200 / 0 / 8,200 / 3,000
                                  P104@P03 6,500 / 0 / 6,500 / 2,500
   18d  Three open customer order lines totalling 7,350 units / INR 4,200,000
   ---------------------------------------------------------------------------
   Nothing here stores the shortage. 7,350 - (8,200 - 3,000) = 2,150 must be
   derived by query.
   =========================================================================== */

/* 18a : flagship purchase order line -------------------------------------- */
DELETE FROM SAP_ERP.PURCHASE_ORDER_LINES WHERE PO_NUMBER = 'PO900001';
INSERT INTO SAP_ERP.PURCHASE_ORDER_LINES
  (PO_NUMBER, PO_LINE_NUMBER, VENDOR_ID, MATERIAL_NO, PLANT_CODE, ORDER_DATE,
   CONFIRMATION_DATE, PROMISED_DATE, ORDER_QTY, UNIT_PRICE, CURRENCY, PO_STATUS)
SELECT 'PO900001', 1, 'S017', 'P104', 'P01',
       DATEADD(day, -18, A), DATEADD(day, -16, A), DATEADD(day, 10, A),
       6000, 395.00, 'CNY', 'OPEN'
FROM (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1);

/* 18b : flagship delayed in-transit shipment ------------------------------- */
DELETE FROM TMS_LOGISTICS.SHIPMENTS WHERE SHIPMENT_ID = 'SH900001';
INSERT INTO TMS_LOGISTICS.SHIPMENTS
  (SHIPMENT_ID, SHIPMENT_LINE_NUMBER, PO_REF, PO_LINE_REF, SUPPLIER_CODE, ITEM_CODE,
   DESTINATION_SITE, CARRIER_CODE, SHIP_DATE, EXPECTED_DELIVERY_DATE,
   ACTUAL_DELIVERY_DATE, PROJECTED_DELIVERY_DATE, SHIPPED_QTY, RECEIVED_QTY,
   FREIGHT_COST, DUTY_COST, HANDLING_COST, OTHER_LOGISTICS_COST,
   TRANSPORT_MODE, SHIPMENT_STATUS)
SELECT 'SH900001', 1, 'PO900001', 1, 'S017', 'P104', 'P01', 'CR11',
       DATEADD(day, -11, A),      -- shipped anchor-11
       DATEADD(day,  10, A),      -- expected anchor+10 (21-day ocean transit)
       NULL,                      -- still in transit
       DATEADD(day,  15, A),      -- projected anchor+15 -> exactly 5 days late
       6000, 0,
       5145.00,                   -- 6000 units x 2.450 kg x 0.35 ocean rate
       154050.00,                 -- 6000 x 395.00 x 6.5% import duty (CN -> IN)
       2350.00,                   -- 250 + 6000 x 0.35
       9480.00,                    -- 6000 x 395.00 x 0.4%
       'Ocean', 'IN_TRANSIT'
FROM (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1);

/* 18c : flagship latest inventory positions -------------------------------- */
UPDATE WMS_INVENTORY.INVENTORY_SNAPSHOTS
   SET ON_HAND_QTY = 8200, RESERVED_QTY = 0, AVAILABLE_QTY = 8200,
       SAFETY_STOCK_QTY = 3000, IN_TRANSIT_QTY = 6000, INVENTORY_STATUS = 'HEALTHY'
 WHERE SKU = 'P104' AND SITE_ID = 'P01'
   AND SNAPSHOT_DATE = (SELECT DATASET_ANCHOR_DATE FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1);

UPDATE WMS_INVENTORY.INVENTORY_SNAPSHOTS
   SET ON_HAND_QTY = 6500, RESERVED_QTY = 0, AVAILABLE_QTY = 6500,
       SAFETY_STOCK_QTY = 2500, IN_TRANSIT_QTY = 0, INVENTORY_STATUS = 'HEALTHY'
 WHERE SKU = 'P104' AND SITE_ID = 'P03'
   AND SNAPSHOT_DATE = (SELECT DATASET_ANCHOR_DATE FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1);

/* 18d : three critical open customer order lines --------------------------- */
DELETE FROM CRM_ORDERS.CUSTOMER_ORDER_LINES
 WHERE ORDER_ID IN ('CO090001','CO090002','CO090003');

INSERT INTO CRM_ORDERS.CUSTOMER_ORDER_LINES
  (ORDER_ID, ORDER_LINE, CUSTOMER_ID, PART_NUMBER, FULFILLMENT_SITE, ORDER_DATE,
   REQUESTED_DATE, DUE_DATE, ORDERED_QTY, FULFILLED_QTY, UNIT_SELL_PRICE,
   ORDER_VALUE, ORDER_STATUS, PRIORITY)
SELECT 'CO090001', 1, 'C0001', 'P104', 'P01',
       DATEADD(day, -22, A), DATEADD(day, 12, A), DATEADD(day, 12, A),
       2500, 0, 569.30, 1423250.00, 'OPEN', 'CRITICAL'
FROM (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1)
UNION ALL
SELECT 'CO090002', 1, 'C0007', 'P104', 'P01',
       DATEADD(day, -20, A), DATEADD(day, 13, A), DATEADD(day, 13, A),
       2400, 0, 570.00, 1368000.00, 'OPEN', 'HIGH'
FROM (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1)
UNION ALL
SELECT 'CO090003', 1, 'C0023', 'P104', 'P01',
       DATEADD(day, -17, A), DATEADD(day, 14, A), DATEADD(day, 14, A),
       2450, 0, 575.00, 1408750.00, 'OPEN', 'HIGH'
FROM (SELECT DATASET_ANCHOR_DATE AS A FROM PUBLIC.DATASET_METADATA WHERE VERSION = 1);

SELECT 'Phase 1 / 03_seed_data.sql complete' AS STATUS;
