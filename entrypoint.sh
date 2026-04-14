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
role      = "VENKATESWARLU_AVVARI_COGNIZANT_COM_ROLE"
warehouse = "DEMO_WH"
database  = "${SNOWFLAKE_DATABASE}"
schema    = "${SNOWFLAKE_SCHEMA}"
EOF
chmod 0600 ~/.snowflake/config.toml

cd /app

# ── Prometheus metrics helper ──────────────────────────────────────────────
push_metric() {
  local metric_name=$1
  local value=$2
  local labels=$3
  if [ -n "${GRAFANA_PROMETHEUS_URL}" ] && [ -n "${GRAFANA_USER}" ] && [ -n "${GRAFANA_API_KEY}" ]; then
    TIMESTAMP=$(date +%s%N)  # nanoseconds for Influx line protocol
    echo "[DEBUG] URL: ${GRAFANA_PROMETHEUS_URL}/api/v1/push/influx/write"
    echo "[DEBUG] USER: ${GRAFANA_USER}"
    echo "[DEBUG] DATA: ${metric_name},${labels// /,} value=${value} ${TIMESTAMP}"
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${GRAFANA_PROMETHEUS_URL}/api/v1/push/influx/write" \
      -u "${GRAFANA_USER}:${GRAFANA_API_KEY}" \
      -H "Content-Type: text/plain" \
      --data-binary "${metric_name},${labels// /,} value=${value} ${TIMESTAMP}")
    echo "[DEBUG] RESPONSE: $RESPONSE"
  fi
}

ENV_LABEL="env=${DBT_TARGET:-dev},job=dbt-sf-cicd"
START_TIME=$(date +%s)

# Deploy dbt object
snow dbt deploy "${DBT_OBJECT_NAME}" --source ./media_dataops --force -c default

# Run dbt
RUN_STATUS=0
snow dbt execute "${DBT_OBJECT_NAME}" run --target "${DBT_TARGET:-dev}" || RUN_STATUS=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Pushing metrics to Grafana: duration=${DURATION} run_status=${RUN_STATUS}"
push_metric "dbt_run_duration_seconds" "$DURATION"   "$ENV_LABEL"
push_metric "dbt_run_status"           "$RUN_STATUS" "$ENV_LABEL"

if [ "$RUN_STATUS" != "0" ]; then
  exit $RUN_STATUS
fi

# Test dbt (only on CI/PR runs)
if [ "${RUN_TESTS:-true}" = "true" ]; then
  TEST_STATUS=0
  snow dbt execute "${DBT_OBJECT_NAME}" test --target "${DBT_TARGET:-dev}" || TEST_STATUS=$?
  echo "Pushing metrics to Grafana: test_status=${TEST_STATUS}"
  push_metric "dbt_test_status" "$TEST_STATUS" "$ENV_LABEL"
  if [ "$TEST_STATUS" != "0" ]; then
    exit $TEST_STATUS
  fi
fi
