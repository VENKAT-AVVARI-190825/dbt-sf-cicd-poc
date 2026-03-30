#!/bin/bash
set -e

# Enable snow dbt feature
export SNOWFLAKE_CLI_FEATURES_ENABLE_DBT=true

# Write Snowflake CLI config from env vars
mkdir -p ~/.snowflake
cat > ~/.snowflake/config.toml <<EOF
[connections.default]
account   = "${SNOWFLAKE_ACCOUNT}"
user      = "${SNOWFLAKE_USER}"
password  = "${SNOWFLAKE_PASSWORD}"
role      = "DATAOPS_ROLE"
warehouse = "MEDIA_WH_XS"
database  = "${SNOWFLAKE_DATABASE}"
schema    = "${SNOWFLAKE_SCHEMA}"
EOF
chmod 0600 ~/.snowflake/config.toml

cd /app

# Deploy dbt object
snow dbt deploy "${DBT_OBJECT_NAME}" --source ./media_dataops --force -c default

# Run dbt
snow dbt execute "${DBT_OBJECT_NAME}" run --target "${DBT_TARGET:-dev}"

# Test dbt (only on CI/PR runs)
if [ "${RUN_TESTS:-true}" = "true" ]; then
  snow dbt execute "${DBT_OBJECT_NAME}" test --target "${DBT_TARGET:-dev}"
fi
