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
-- Step 2: Create OIDC Service User for GitHub Actions
-- ============================================================

CREATE USER IF NOT EXISTS GitHub_Actions_Service_User
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (
    TYPE   = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com',
    SUBJECT = 'repo:<your_repo_org>/<your_dbt_repo>:environment:prod'
  )
  DEFAULT_ROLE      = DATAOPS_ROLE
  DEFAULT_WAREHOUSE = MEDIA_WH_XS
  COMMENT           = 'Service User For GitHub Actions';

-- Set default warehouse
ALTER USER GitHub_Actions_Service_User SET DEFAULT_WAREHOUSE = MEDIA_WH_XS;

-- Grant role to service user
GRANT ROLE DATAOPS_ROLE TO USER GitHub_Actions_Service_User;


-- ============================================================
-- Step 3: Network Policy (optional — only if IP restrictions apply)
-- ============================================================

-- Option 1: Create new policy and apply to service user
CREATE NETWORK POLICY IF NOT EXISTS github_actions_policy
  ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
  BLOCKED_NETWORK_RULE_LIST = ();

ALTER USER GitHub_Actions_Service_User SET NETWORK_POLICY = github_actions_policy;

-- Verify policy is applied
SHOW PARAMETERS LIKE 'NETWORK_POLICY' FOR USER GitHub_Actions_Service_User;

-- Option 2: Add rule to an existing network policy
-- SHOW PARAMETERS LIKE 'NETWORK_POLICY' FOR USER <your_user_name>;
-- ALTER NETWORK POLICY <existing_policy_name>
--   ADD ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL');
