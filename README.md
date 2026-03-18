# dbt + Snowflake CI/CD POC
Based on: [Automate Your dbt Project on Snowflake](https://medium.com/@uche.nkadi/automate-your-dbt-project-on-snowflake-a-practical-guide-to-github-actions-ci-cd-a366b6e061e5)

## Project Structure

```
dbt-sf-cicd-poc/
├── .github/
│   └── workflows/
│       ├── incoming_pr.yml       # CI: lint + run + test on dev (on PR)
│       └── pr_merged.yml         # CD: deploy to prod (on merge to main)
├── media_dataops/                # dbt project folder
│   ├── models/
│   │   ├── media_events.sql
│   │   └── schema.yml
│   ├── dbt_project.yml
│   ├── profiles.yml              # placeholder values — overwritten by OIDC + secrets
│   └── schedules.sql             # optional: Snowflake Task orchestration (Step 7)
├── snowflake_setup.sql           # Snowflake setup: DB, schema, OIDC user, network policy
└── README.md
```

## Setup Steps

### Step 1 — Snowflake: Run snowflake_setup.sql
Run `snowflake_setup.sql` on Snowsight to create databases, schemas, OIDC service user, and (optionally) network policy.

### Step 2 — GitHub: Repository Secrets
Go to **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | e.g. `orgname-accountname` |

> With OIDC, no `SNOWFLAKE_USER` or `SNOWFLAKE_PASSWORD` secret is needed.

### Step 3 — GitHub: Repository Variables
Go to **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `SNOWFLAKE_DATABASE` | `media_dataops_dev_dbt_DB` |
| `SNOWFLAKE_SCHEMA` | `dev_schema` |

### Step 4 — GitHub: Create Environment
Go to **Settings → Environments** and create an environment named `prod`.
This must match the `environment: prod` in both workflow files and the OIDC subject.

## CI/CD Flow

```
PR opened/updated → incoming_pr.yml
  └── Install Snowflake CLI (OIDC)
  └── snow dbt deploy  → creates TESTER dbt object on dev schema
  └── snow dbt execute → run  --target dev
  └── snow dbt execute → test --target dev
  └── ✅ Pass = PR can be merged | ❌ Fail = PR blocked

Merge to main → pr_merged.yml
  └── Install Snowflake CLI (OIDC)
  └── snow dbt deploy  → creates/updates PROD dbt object
  └── (optional) snow sql schedules.sql → creates Snowflake Tasks
```

## Step 7 (Optional): Task Orchestration
Uncomment the schedules step in `pr_merged.yml` to manage Snowflake Task orchestration via source control using `media_dataops/schedules.sql`.
