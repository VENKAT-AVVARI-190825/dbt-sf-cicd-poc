-- ============================================================
-- Run as ACCOUNTADMIN
-- ============================================================
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- Step 1: Drop Network Policy
-- ============================================================
ALTER USER GITHUB_ACTIONS_SERVICE_USER UNSET NETWORK_POLICY;
DROP NETWORK POLICY IF EXISTS github_actions_policy;

-- ============================================================
-- Step 2: Drop Service User
-- ============================================================
DROP USER IF EXISTS GITHUB_ACTIONS_SERVICE_USER;

-- ============================================================
-- Step 3: Drop Stages and File Formats (dev)
-- ============================================================
DROP STAGE       IF EXISTS media_dataops_dev_dbt_DB.dev_schema.media_raw_stage;
DROP FILE FORMAT IF EXISTS media_dataops_dev_dbt_DB.dev_schema.json_format;

-- ============================================================
-- Step 4: Drop Stages and File Formats (prod)
-- ============================================================
DROP STAGE       IF EXISTS media_dataops_prod_dbt_DB.prod_schema.media_raw_stage;
DROP FILE FORMAT IF EXISTS media_dataops_prod_dbt_DB.prod_schema.json_format;

-- ============================================================
-- Step 5: Drop Schemas
-- ============================================================
DROP SCHEMA IF EXISTS media_dataops_dev_dbt_DB.dev_schema;
DROP SCHEMA IF EXISTS media_dataops_prod_dbt_DB.prod_schema;

-- ============================================================
-- Step 6: Drop Databases (cascades all objects inside)
-- ============================================================
DROP DATABASE IF EXISTS media_dataops_dev_dbt_DB;
DROP DATABASE IF EXISTS media_dataops_prod_dbt_DB;

-- ============================================================
-- Step 7: Drop Warehouses
-- ============================================================
DROP WAREHOUSE IF EXISTS MEDIA_WH_XS;
DROP WAREHOUSE IF EXISTS MEDIA_WH_MD;

-- ============================================================
-- Step 8: Drop Role
-- ============================================================
DROP ROLE IF EXISTS DATAOPS_ROLE;
