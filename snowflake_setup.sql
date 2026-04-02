-- ============================================================
-- Step 1: Create Databases and Schemas
-- ============================================================

-- Option 1: Clone production database (zero-copy, cost-effective)
-- CREATE DATABASE media_dataops_dev_dbt_DB CLONE YOUR_PRODUCTION_DATABASE;

-- Option 2: Clone specific schemas only
-- CREATE DATABASE media_dataops_dev_dbt_DB;
-- CREATE SCHEMA media_dataops_dev_dbt_DB.dev CLONE YOUR_PRODUCTION_DATABASE.YOUR_SCHEMA_NAME;

-- Option 3: Fresh databases and schemas (used in this POC)
CREATE DATABASE IF NOT EXISTS media_dataops_dev_dbt_DB;
CREATE SCHEMA  IF NOT EXISTS media_dataops_dev_dbt_DB.dev_schema;

CREATE DATABASE IF NOT EXISTS media_dataops_prod_dbt_DB;
CREATE SCHEMA  IF NOT EXISTS media_dataops_prod_dbt_DB.prod_schema;


-- ============================================================
-- Step 2: Create Role and Warehouses
-- ============================================================

CREATE ROLE IF NOT EXISTS DATAOPS_ROLE;

CREATE WAREHOUSE IF NOT EXISTS MEDIA_WH_XS
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;

CREATE WAREHOUSE IF NOT EXISTS MEDIA_WH_MD
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;


-- ============================================================
-- Step 3: Grant Privileges to DATAOPS_ROLE
-- ============================================================

-- Warehouse access
GRANT USAGE ON WAREHOUSE MEDIA_WH_XS TO ROLE DATAOPS_ROLE;
GRANT USAGE ON WAREHOUSE MEDIA_WH_MD TO ROLE DATAOPS_ROLE;

-- Database access
GRANT ALL PRIVILEGES ON DATABASE media_dataops_dev_dbt_DB  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON DATABASE media_dataops_prod_dbt_DB TO ROLE DATAOPS_ROLE;

-- Schema access
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE media_dataops_dev_dbt_DB  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE media_dataops_prod_dbt_DB TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE media_dataops_dev_dbt_DB  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE media_dataops_prod_dbt_DB TO ROLE DATAOPS_ROLE;

-- Table access
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema   TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema   TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema TO ROLE DATAOPS_ROLE;


-- ============================================================
-- Step 4: Create Stage and File Format
-- ============================================================

USE DATABASE media_dataops_dev_dbt_DB;
USE SCHEMA dev_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;

GRANT ALL ON STAGE media_raw_stage      TO ROLE DATAOPS_ROLE;
GRANT ALL ON FILE FORMAT json_format    TO ROLE DATAOPS_ROLE;

-- Prod stage and file format
USE DATABASE media_dataops_prod_dbt_DB;
USE SCHEMA prod_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;

GRANT ALL ON STAGE media_raw_stage      TO ROLE DATAOPS_ROLE;
GRANT ALL ON FILE FORMAT json_format    TO ROLE DATAOPS_ROLE;


-- ============================================================
-- Step 5: Create Service User for GitHub Actions (password auth)
-- ============================================================

-- Note: Originally created as SERVICE type with OIDC but switched
-- to PERSON type with password auth for ECS Fargate compatibility

CREATE USER IF NOT EXISTS GITHUB_ACTIONS_SERVICE_USER
  DEFAULT_ROLE      = DATAOPS_ROLE
  DEFAULT_WAREHOUSE = MEDIA_WH_XS
  COMMENT           = 'Service User For GitHub Actions / ECS Fargate';

-- If user was previously created as SERVICE type with WORKLOAD_IDENTITY, run:
-- ALTER USER GITHUB_ACTIONS_SERVICE_USER UNSET WORKLOAD_IDENTITY;
-- ALTER USER GITHUB_ACTIONS_SERVICE_USER SET TYPE = PERSON PASSWORD = '<your_password>';

ALTER USER GITHUB_ACTIONS_SERVICE_USER SET PASSWORD = '<your_password>';

GRANT ROLE DATAOPS_ROLE TO USER GITHUB_ACTIONS_SERVICE_USER;
GRANT ROLE DATAOPS_ROLE TO USER <your_personal_snowflake_user>;


-- ============================================================
-- Step 6: Network Policy (optional)
-- ============================================================

-- Created but later unset for ECS Fargate compatibility
-- (Fargate IPs are dynamic and not in the GitHub Actions IP range)

-- CREATE NETWORK POLICY IF NOT EXISTS github_actions_policy
--   ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
--   BLOCKED_NETWORK_RULE_LIST = ();

-- To unset network policy from service user (required for ECS Fargate):
-- ALTER USER GITHUB_ACTIONS_SERVICE_USER UNSET NETWORK_POLICY;
