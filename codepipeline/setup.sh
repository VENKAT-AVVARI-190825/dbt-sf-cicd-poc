#!/bin/bash
# Run this once to set up CodePipeline + CodeBuild for dbt-sf-cicd
# Prerequisites: AWS CLI configured, ECR repo and ECS cluster already exist

set -e

ACCOUNT_ID="691879165105"
REGION="us-east-2"
ECR_REPO="dbt-sf-cicd"

# ============================================================
# Step 1: Store secrets in SSM Parameter Store
# ============================================================
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_ACCOUNT   --value "<snowflake_account>"        --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_USER       --value "<snowflake_user>"           --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_PASSWORD   --value "<snowflake_password>"       --type SecureString --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_DATABASE   --value "media_dataops_dev_dbt_DB"   --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_SCHEMA     --value "dev_schema"                 --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_DATABASE_PROD --value "media_dataops_prod_dbt_DB" --type String     --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/SNOWFLAKE_SCHEMA_PROD   --value "prod_schema"             --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/ECS_CLUSTER          --value "dbt-sf-cicd-cluster"        --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/ECS_TASK_DEFINITION  --value "dbt-sf-cicd"                --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/ECS_SUBNET           --value "<subnet_id>"                --type String       --overwrite --region $REGION
aws ssm put-parameter --name /dbt-sf-cicd/ECS_SECURITY_GROUP   --value "<security_group_id>"        --type String       --overwrite --region $REGION

# ============================================================
# Step 2: Create CodeBuild IAM role
# ============================================================
aws iam create-role \
  --role-name CodeBuild-dbt-sf-cicd-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "codebuild.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' --region $REGION

aws iam attach-role-policy \
  --role-name CodeBuild-dbt-sf-cicd-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

aws iam attach-role-policy \
  --role-name CodeBuild-dbt-sf-cicd-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess

aws iam attach-role-policy \
  --role-name CodeBuild-dbt-sf-cicd-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# ============================================================
# Step 3: Create CodeBuild projects
# ============================================================
aws codebuild create-project \
  --name dbt-sf-cicd-dev \
  --source '{"type": "NO_SOURCE", "buildspec": "codepipeline/buildspec-dev.yml"}' \
  --artifacts '{"type": "NO_ARTIFACTS"}' \
  --environment '{"type": "LINUX_CONTAINER", "computeType": "BUILD_GENERAL1_SMALL", "image": "aws/codebuild/standard:7.0"}' \
  --service-role arn:aws:iam::$ACCOUNT_ID:role/CodeBuild-dbt-sf-cicd-role \
  --region $REGION

aws codebuild create-project \
  --name dbt-sf-cicd-prod \
  --source '{"type": "NO_SOURCE", "buildspec": "codepipeline/buildspec-prod.yml"}' \
  --artifacts '{"type": "NO_ARTIFACTS"}' \
  --environment '{"type": "LINUX_CONTAINER", "computeType": "BUILD_GENERAL1_SMALL", "image": "aws/codebuild/standard:7.0"}' \
  --service-role arn:aws:iam::$ACCOUNT_ID:role/CodeBuild-dbt-sf-cicd-role \
  --region $REGION

# ============================================================
# Step 4: Create CodePipeline IAM role
# ============================================================
aws iam create-role \
  --role-name CodePipeline-dbt-sf-cicd-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "codepipeline.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' --region $REGION

aws iam attach-role-policy \
  --role-name CodePipeline-dbt-sf-cicd-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess

aws iam attach-role-policy \
  --role-name CodePipeline-dbt-sf-cicd-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# ============================================================
# Step 5: Create CodePipelines (ECR as source, CodeBuild as deploy)
# ============================================================
aws codepipeline create-pipeline \
  --pipeline "{
    \"name\": \"dbt-sf-cicd-dev\",
    \"roleArn\": \"arn:aws:iam::$ACCOUNT_ID:role/CodePipeline-dbt-sf-cicd-role\",
    \"artifactStore\": {\"type\": \"S3\", \"location\": \"codepipeline-$REGION-$ACCOUNT_ID\"},
    \"stages\": [
      {
        \"name\": \"Source\",
        \"actions\": [{
          \"name\": \"ECR\",
          \"actionTypeId\": {\"category\": \"Source\", \"owner\": \"AWS\", \"provider\": \"ECR\", \"version\": \"1\"},
          \"configuration\": {\"RepositoryName\": \"$ECR_REPO\", \"ImageTag\": \"latest\"},
          \"outputArtifacts\": [{\"name\": \"SourceOutput\"}]
        }]
      },
      {
        \"name\": \"Deploy\",
        \"actions\": [{
          \"name\": \"RunFargateTask\",
          \"actionTypeId\": {\"category\": \"Build\", \"owner\": \"AWS\", \"provider\": \"CodeBuild\", \"version\": \"1\"},
          \"configuration\": {\"ProjectName\": \"dbt-sf-cicd-dev\"},
          \"inputArtifacts\": [{\"name\": \"SourceOutput\"}]
        }]
      }
    ]
  }" --region $REGION

aws codepipeline create-pipeline \
  --pipeline "{
    \"name\": \"dbt-sf-cicd-prod\",
    \"roleArn\": \"arn:aws:iam::$ACCOUNT_ID:role/CodePipeline-dbt-sf-cicd-role\",
    \"artifactStore\": {\"type\": \"S3\", \"location\": \"codepipeline-$REGION-$ACCOUNT_ID\"},
    \"stages\": [
      {
        \"name\": \"Source\",
        \"actions\": [{
          \"name\": \"ECR\",
          \"actionTypeId\": {\"category\": \"Source\", \"owner\": \"AWS\", \"provider\": \"ECR\", \"version\": \"1\"},
          \"configuration\": {\"RepositoryName\": \"$ECR_REPO\", \"ImageTag\": \"latest\"},
          \"outputArtifacts\": [{\"name\": \"SourceOutput\"}]
        }]
      },
      {
        \"name\": \"Deploy\",
        \"actions\": [{
          \"name\": \"RunFargateTask\",
          \"actionTypeId\": {\"category\": \"Build\", \"owner\": \"AWS\", \"provider\": \"CodeBuild\", \"version\": \"1\"},
          \"configuration\": {\"ProjectName\": \"dbt-sf-cicd-prod\"},
          \"inputArtifacts\": [{\"name\": \"SourceOutput\"}]
        }]
      }
    ]
  }" --region $REGION

echo "Done. CodePipeline dev and prod pipelines created."
echo "Both pipelines will auto-trigger when a new image is pushed to ECR."
