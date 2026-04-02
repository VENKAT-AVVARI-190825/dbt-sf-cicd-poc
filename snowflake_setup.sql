-- ============================================================
-- Run as ACCOUNTADMIN
-- ============================================================
USE ROLE ACCOUNTADMIN;


-- ============================================================
-- Step 1: Create Databases and Schemas
-- ============================================================

CREATE DATABASE IF NOT EXISTS media_dataops_dev_dbt_DB;
CREATE SCHEMA  IF NOT EXISTS media_dataops_dev_dbt_DB.dev_schema;

CREATE DATABASE IF NOT EXISTS media_dataops_prod_dbt_DB;
CREATE SCHEMA  IF NOT EXISTS media_dataops_prod_dbt_DB.prod_schema;


-- ============================================================
-- Step 2: Create Role
-- ============================================================

CREATE ROLE IF NOT EXISTS DATAOPS_ROLE;


-- ============================================================
-- Step 3: Create Warehouses
-- ============================================================

CREATE WAREHOUSE IF NOT EXISTS MEDIA_WH_XS
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;

CREATE WAREHOUSE IF NOT EXISTS MEDIA_WH_MD
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;


-- ============================================================
-- Step 4: Grant Privileges to DATAOPS_ROLE
-- ============================================================

-- Warehouses
GRANT USAGE ON WAREHOUSE MEDIA_WH_XS TO ROLE DATAOPS_ROLE;
GRANT USAGE ON WAREHOUSE MEDIA_WH_MD TO ROLE DATAOPS_ROLE;

-- Databases
GRANT ALL PRIVILEGES ON DATABASE media_dataops_dev_dbt_DB  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON DATABASE media_dataops_prod_dbt_DB TO ROLE DATAOPS_ROLE;

-- Schemas
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE media_dataops_dev_dbt_DB    TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE media_dataops_prod_dbt_DB   TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE media_dataops_dev_dbt_DB  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE media_dataops_prod_dbt_DB TO ROLE DATAOPS_ROLE;

-- Tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema    TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema  TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema   TO ROLE DATAOPS_ROLE;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema TO ROLE DATAOPS_ROLE;


-- ============================================================
-- Step 5: Create Stage and File Format (dev)
-- ============================================================

USE DATABASE media_dataops_dev_dbt_DB;
USE SCHEMA dev_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;

GRANT ALL ON FILE FORMAT json_format TO ROLE DATAOPS_ROLE;
GRANT ALL ON STAGE media_raw_stage   TO ROLE DATAOPS_ROLE;


-- ============================================================
-- Step 6: Create Stage and File Format (prod)
-- ============================================================

USE DATABASE media_dataops_prod_dbt_DB;
USE SCHEMA prod_schema;

CREATE FILE FORMAT IF NOT EXISTS json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

CREATE STAGE IF NOT EXISTS media_raw_stage
  FILE_FORMAT = json_format;

GRANT ALL ON FILE FORMAT json_format TO ROLE DATAOPS_ROLE;
GRANT ALL ON STAGE media_raw_stage   TO ROLE DATAOPS_ROLE;


-- ============================================================
-- Step 7: Create Service User for GitHub Actions / ECS Fargate
-- ============================================================

-- Originally created as SERVICE type with OIDC but switched to
-- PERSON type with password auth for ECS Fargate compatibility

CREATE USER IF NOT EXISTS GITHUB_ACTIONS_SERVICE_USER
  DEFAULT_ROLE      = DATAOPS_ROLE
  DEFAULT_WAREHOUSE = MEDIA_WH_XS
  COMMENT           = 'Service User For GitHub Actions / ECS Fargate';

-- Remove OIDC workload identity and switch to password auth
ALTER USER GITHUB_ACTIONS_SERVICE_USER UNSET WORKLOAD_IDENTITY;
ALTER USER GITHUB_ACTIONS_SERVICE_USER SET TYPE = PERSON PASSWORD = '<your_password>';

-- Grant role
GRANT ROLE DATAOPS_ROLE TO USER GITHUB_ACTIONS_SERVICE_USER;

-- Grant role to your personal Snowflake user for querying
GRANT ROLE DATAOPS_ROLE TO USER <your_personal_snowflake_user>;

-- Grant table ownership to DATAOPS_ROLE (run if table was created by another role)
-- GRANT OWNERSHIP ON TABLE media_dataops_dev_dbt_DB.dev_schema.media_events
--   TO ROLE DATAOPS_ROLE COPY CURRENT GRANTS;


-- ============================================================
-- Step 8: Network Policy
-- ============================================================

-- Created but unset for ECS Fargate compatibility
-- (Fargate IPs are dynamic and outside the GitHub Actions IP range)

CREATE NETWORK POLICY IF NOT EXISTS github_actions_policy
  ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
  BLOCKED_NETWORK_RULE_LIST = ();

ALTER USER GITHUB_ACTIONS_SERVICE_USER SET NETWORK_POLICY = github_actions_policy;

-- Unset network policy to allow ECS Fargate IPs
ALTER USER GITHUB_ACTIONS_SERVICE_USER UNSET NETWORK_POLICY;

-- Verify
SHOW PARAMETERS LIKE 'NETWORK_POLICY' FOR USER GITHUB_ACTIONS_SERVICE_USER;


-- ============================================================
-- Step 9: Verification Queries
-- ============================================================

-- Check user setup
SHOW USERS LIKE 'GITHUB%';

-- Check role grants
SHOW GRANTS TO ROLE DATAOPS_ROLE;

-- Check dbt project objects in dev
SHOW DBT PROJECTS IN DATABASE media_dataops_dev_dbt_DB;

-- Check dbt project objects in prod
SHOW DBT PROJECTS IN DATABASE media_dataops_prod_dbt_DB;

-- Check tables
SHOW TABLES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema;
SHOW TABLES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema;

-- Check stages
SHOW STAGES IN SCHEMA media_dataops_dev_dbt_DB.dev_schema;
SHOW STAGES IN SCHEMA media_dataops_prod_dbt_DB.prod_schema;

-- Check network policy
SHOW PARAMETERS LIKE 'NETWORK_POLICY' FOR USER GITHUB_ACTIONS_SERVICE_USER;

-- Query data
USE ROLE DATAOPS_ROLE;
SELECT * FROM media_dataops_dev_dbt_DB.dev_schema.media_events LIMIT 10;
SELECT * FROM media_dataops_prod_dbt_DB.prod_schema.media_events LIMIT 10;
