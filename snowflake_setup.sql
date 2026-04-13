-- ============================================================
-- Snowflake Setup for dbt CI/CD POC
-- Account: RMHNYOB-COGNIZANT_INDIA
-- Run as: VENKATESWARLU.AVVARI@COGNIZANT.COM
-- Note: No ACCOUNTADMIN required — uses existing DB, warehouse and role
-- ============================================================

USE ROLE    VENKATESWARLU_AVVARI_COGNIZANT_COM_ROLE;
USE WAREHOUSE DEMO_WH;
USE DATABASE  VENKATESWARLU_AVVARI_COGNIZANT_COM_DB;


-- ============================================================
-- Step 1: Create Schemas
-- ============================================================

CREATE SCHEMA IF NOT EXISTS VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema;
CREATE SCHEMA IF NOT EXISTS VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema;


-- ============================================================
-- Step 2: Create Stage and File Format (dev)
-- ============================================================

USE SCHEMA VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;


-- ============================================================
-- Step 3: Create Stage and File Format (prod)
-- ============================================================

USE SCHEMA VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;


-- ============================================================
-- Step 4: Load Sample Data (dev)
-- ============================================================

USE SCHEMA VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema;

-- Upload sample_events.json via SnowSQL CLI:
-- PUT file:///path/to/sample_events.json @media_raw_stage;

-- Verify data in stage
SELECT $1 FROM @media_raw_stage (FILE_FORMAT => 'json_format');

-- Truncate table before full reload (handles NULL MAX issue in incremental model)
TRUNCATE TABLE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema.media_events;


-- ============================================================
-- Step 5: Verification Queries
-- ============================================================

SHOW SCHEMAS IN DATABASE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB;
SHOW STAGES  IN SCHEMA   VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema;
SHOW STAGES  IN SCHEMA   VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema;
SHOW DBT PROJECTS IN DATABASE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB;

-- Query data after dbt run
SELECT * FROM VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema.media_events  LIMIT 10;
SELECT * FROM VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema.media_events LIMIT 10;
