terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.90"
    }
  }
}

provider "snowflake" {
  account  = var.snowflake_account
  username = var.snowflake_user
  password = var.snowflake_password
  role     = "ACCOUNTADMIN"
}

# ============================================================
# Databases and Schemas
# ============================================================

resource "snowflake_database" "dev" {
  name = "MEDIA_DATAOPS_DEV_DBT_DB"
}

resource "snowflake_database" "prod" {
  name = "MEDIA_DATAOPS_PROD_DBT_DB"
}

resource "snowflake_schema" "dev" {
  database = snowflake_database.dev.name
  name     = "DEV_SCHEMA"
}

resource "snowflake_schema" "prod" {
  database = snowflake_database.prod.name
  name     = "PROD_SCHEMA"
}

# ============================================================
# Role
# ============================================================

resource "snowflake_role" "dataops" {
  name = "DATAOPS_ROLE"
}

# ============================================================
# Warehouses
# ============================================================

resource "snowflake_warehouse" "xs" {
  name           = "MEDIA_WH_XS"
  warehouse_size = "X-SMALL"
  auto_suspend   = 60
  auto_resume    = true
}

resource "snowflake_warehouse" "md" {
  name           = "MEDIA_WH_MD"
  warehouse_size = "MEDIUM"
  auto_suspend   = 60
  auto_resume    = true
}

# ============================================================
# Warehouse Grants
# ============================================================

resource "snowflake_warehouse_grant" "xs" {
  warehouse_name = snowflake_warehouse.xs.name
  privilege      = "USAGE"
  roles          = [snowflake_role.dataops.name]
}

resource "snowflake_warehouse_grant" "md" {
  warehouse_name = snowflake_warehouse.md.name
  privilege      = "USAGE"
  roles          = [snowflake_role.dataops.name]
}

# ============================================================
# Database Grants
# ============================================================

resource "snowflake_database_grant" "dev" {
  database_name = snowflake_database.dev.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}

resource "snowflake_database_grant" "prod" {
  database_name = snowflake_database.prod.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}

# ============================================================
# Schema Grants
# ============================================================

resource "snowflake_schema_grant" "dev" {
  database_name = snowflake_database.dev.name
  schema_name   = snowflake_schema.dev.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}

resource "snowflake_schema_grant" "prod" {
  database_name = snowflake_database.prod.name
  schema_name   = snowflake_schema.prod.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}

# ============================================================
# Service User
# ============================================================

resource "snowflake_user" "github_actions" {
  name              = "GITHUB_ACTIONS_SERVICE_USER"
  password          = var.service_user_password
  default_role      = snowflake_role.dataops.name
  default_warehouse = snowflake_warehouse.xs.name
  comment           = "Service User For GitHub Actions / ECS Fargate"
}

resource "snowflake_role_grants" "github_actions" {
  role_name = snowflake_role.dataops.name
  users     = [snowflake_user.github_actions.name]
}

# ============================================================
# Stages and File Formats
# ============================================================

resource "snowflake_file_format" "json_dev" {
  name              = "JSON_FORMAT"
  database          = snowflake_database.dev.name
  schema            = snowflake_schema.dev.name
  format_type       = "JSON"
  strip_outer_array = true
}

resource "snowflake_file_format" "json_prod" {
  name              = "JSON_FORMAT"
  database          = snowflake_database.prod.name
  schema            = snowflake_schema.prod.name
  format_type       = "JSON"
  strip_outer_array = true
}

resource "snowflake_stage" "dev" {
  name        = "MEDIA_RAW_STAGE"
  database    = snowflake_database.dev.name
  schema      = snowflake_schema.dev.name
  file_format = "FORMAT_NAME = ${snowflake_database.dev.name}.${snowflake_schema.dev.name}.${snowflake_file_format.json_dev.name}"
}

resource "snowflake_stage" "prod" {
  name        = "MEDIA_RAW_STAGE"
  database    = snowflake_database.prod.name
  schema      = snowflake_schema.prod.name
  file_format = "FORMAT_NAME = ${snowflake_database.prod.name}.${snowflake_schema.prod.name}.${snowflake_file_format.json_prod.name}"
}

# ============================================================
# Stage Grants
# ============================================================

resource "snowflake_stage_grant" "dev" {
  database_name = snowflake_database.dev.name
  schema_name   = snowflake_schema.dev.name
  stage_name    = snowflake_stage.dev.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}

resource "snowflake_stage_grant" "prod" {
  database_name = snowflake_database.prod.name
  schema_name   = snowflake_schema.prod.name
  stage_name    = snowflake_stage.prod.name
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.dataops.name]
}
