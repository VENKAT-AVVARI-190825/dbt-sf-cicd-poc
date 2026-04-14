#!/bin/bash
# Sets up observability: Lambda (CloudWatch -> Splunk) + SSM params for Grafana
set -e

ACCOUNT_ID="691879165105"
REGION="us-east-2"
LOG_GROUP="/ecs/dbt-sf-cicd"
LAMBDA_NAME="dbt-sf-cicd-splunk-forwarder"
LAMBDA_ROLE="CCL-Lambda-Role"  # existing role with AWSLambdaFullAccess

# ============================================================
# Step 1: Store Grafana + Splunk config in SSM
# ============================================================
aws ssm put-parameter --name /dbt-sf-cicd/GRAFANA_PROMETHEUS_URL --value "<grafana_remote_write_base_url>"  --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/GRAFANA_USER           --value "<grafana_numeric_user_id>"        --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/GRAFANA_API_KEY        --value "<grafana_service_account_token>"  --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SPLUNK_HEC_URL         --value "<splunk_hec_url>"                 --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SPLUNK_HEC_TOKEN       --value "<splunk_hec_token>"               --type SecureString --overwrite --region $REGION

# ============================================================
# Step 2: Package and deploy Lambda
# ============================================================
cd "$(dirname "$0")"
zip lambda_splunk.zip lambda_splunk.py

aws lambda create-function \
  --function-name $LAMBDA_NAME \
  --runtime python3.11 \
  --role arn:aws:iam::$ACCOUNT_ID:role/$LAMBDA_ROLE \
  --handler lambda_splunk.lambda_handler \
  --zip-file fileb://lambda_splunk.zip \
  --environment "Variables={
    SPLUNK_HEC_URL=$(aws ssm get-parameter --name /dbt-sf-cicd/SPLUNK_HEC_URL --with-decryption --query 'Parameter.Value' --output text --region $REGION),
    SPLUNK_HEC_TOKEN=$(aws ssm get-parameter --name /dbt-sf-cicd/SPLUNK_HEC_TOKEN --with-decryption --query 'Parameter.Value' --output text --region $REGION)
  }" \
  --region $REGION

rm lambda_splunk.zip

# ============================================================
# Step 3: Allow CloudWatch Logs to invoke Lambda
# ============================================================
aws lambda add-permission \
  --function-name $LAMBDA_NAME \
  --statement-id cloudwatch-logs \
  --action lambda:InvokeFunction \
  --principal logs.amazonaws.com \
  --source-arn arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$LOG_GROUP:* \
  --region $REGION

# ============================================================
# Step 4: Create CloudWatch Logs subscription filter
# ============================================================
aws logs put-subscription-filter \
  --log-group-name $LOG_GROUP \
  --filter-name dbt-sf-cicd-to-splunk \
  --filter-pattern "" \
  --destination-arn arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$LAMBDA_NAME \
  --region $REGION

echo "Done. CloudWatch logs from $LOG_GROUP will now forward to Splunk."
