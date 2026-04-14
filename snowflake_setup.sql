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

-- Upload sample_events.json:
COPY FILES INTO @VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.DEV_SCHEMA.MEDIA_RAW_STAGE FROM 'snow://workspace/USER$.PUBLIC."Coco_HOL"/versions/live/' FILES=('sample_events.json');

-- Verify data in stage
SELECT $1 FROM @VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.DEV_SCHEMA.MEDIA_RAW_STAGE/sample_events.json (FILE_FORMAT => 'VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.DEV_SCHEMA.JSON_FORMAT') LIMIT 5;

CREATE TABLE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.DEV_SCHEMA.MEDIA_EVENTS (
    EVENT_ID STRING,
    EVENT_TYPE STRING,
    INGESTED_AT TIMESTAMP,
    MEDIA_ASSET_ID STRING,
    REGION STRING,
    SOURCE_KEY STRING,
    USER_ID STRING
);
-- Truncate table before full reload (handles NULL MAX issue in incremental model)
TRUNCATE TABLE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.dev_schema.media_events;

USE SCHEMA VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema;

-- Upload sample_events.json:
COPY FILES INTO @VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.PROD_SCHEMA.MEDIA_RAW_STAGE FROM 'snow://workspace/USER$.PUBLIC."Coco_HOL"/versions/live/' FILES=('sample_events.json');

-- Verify data in stage
SELECT $1 FROM @VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.PROD_SCHEMA.MEDIA_RAW_STAGE/sample_events.json (FILE_FORMAT => 'VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.PROD_SCHEMA.JSON_FORMAT') LIMIT 5;

CREATE TABLE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.PROD_SCHEMA.MEDIA_EVENTS (
    EVENT_ID STRING,
    EVENT_TYPE STRING,
    INGESTED_AT TIMESTAMP,
    MEDIA_ASSET_ID STRING,
    REGION STRING,
    SOURCE_KEY STRING,
    USER_ID STRING
);

TRUNCATE TABLE VENKATESWARLU_AVVARI_COGNIZANT_COM_DB.prod_schema.media_events;

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
