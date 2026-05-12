# Sky — GCP BigQuery → AWS Snowflake Migration

**Project:** Project Peacock — Lift & Shift from GCP/BigQuery to AWS/Snowflake
**Document purpose:** High-level architecture, end-to-end data flow, and Milestone 1 delivery view.
**Audience:** Sky stakeholders, Cognizant delivery team.

---

## 1. Executive Summary

Cognizant is delivering a fixed-capacity SRE + Data Engineering pod to migrate Sky's analytics platform from **GCP BigQuery** to **AWS + Snowflake**, using **open Iceberg tables on S3** for storage and **dbt** as the single transformation layer across the migration. CI/CD is GitHub Actions with OIDC-based authentication to Snowflake (no static credentials). Observability is split: **Splunk Cloud** for logs and **Grafana Cloud** for metrics, integrating into Sky's existing operational tooling.

**Why this shape:**
- **Iceberg on S3** keeps data in an open format — no vendor lock-in; any engine can read the same files later.
- **dbt unchanged** means most BigQuery transformation logic lifts and shifts with macro shims, not rewrites.
- **OIDC + PrivateLink** removes static secrets and public-internet traffic — Sky's security posture stays intact.
- **One ETL end-to-end** is the Milestone 1 acceptance gate, not "all jobs migrated" — de-risks scope.

---

## 2. High-Level Architecture

### 2.1 Source vs. Target

| Concern | Current (GCP) | Target (AWS + Snowflake) |
|---|---|---|
| Compute | BigQuery | Snowflake on AWS |
| Storage | BigQuery native + GCS | S3 + Snowflake Iceberg Tables |
| Transformation | dbt on BigQuery | dbt on Snowflake |
| Orchestration | Sky's current scheduler | Snowflake Tasks / external scheduler |
| CI/CD | Existing | GitHub Actions + Snowflake CLI (OIDC) |
| Observability | Existing | Splunk Cloud (logs) + Grafana Cloud (metrics) |

### 2.2 Layered View

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CONSUMERS (Sky)                                │
│        BI tools  ·  Reverse-ETL  ·  Analysts  ·  Downstream apps        │
└────────────────────────────────▲────────────────────────────────────────┘
                                 │  SQL / Snowflake roles (RBAC)
┌────────────────────────────────┴────────────────────────────────────────┐
│                       SERVING LAYER — Snowflake                         │
│   prod_schema   ·   marts (dbt models)   ·   Snowflake Catalog          │
└────────────────────────────────▲────────────────────────────────────────┘
                                 │  dbt run (incremental / full refresh)
┌────────────────────────────────┴────────────────────────────────────────┐
│                  TRANSFORMATION — dbt on Snowflake                      │
│   media_dataops/  ·  models · macros · tests · schedules.sql            │
│   Environments: dev_schema / prod_schema                                │
└────────────────────────────────▲────────────────────────────────────────┘
                                 │  External tables / COPY INTO
┌────────────────────────────────┴────────────────────────────────────────┐
│                       STORAGE LAYER — AWS                               │
│   S3 raw zone (Iceberg)  ·  Storage Integration  ·  KMS encryption      │
└────────────────────────────────▲────────────────────────────────────────┘
                                 │  History load + ongoing ingestion
┌────────────────────────────────┴────────────────────────────────────────┐
│                          MIGRATION PIPELINE                             │
│   BigQuery export → GCS → S3 (DataSync / Storage Transfer)              │
│   BQ schema → Iceberg DDL  ·  DBT jobs re-pointed BQ → Snowflake        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Cross-Cutting Planes

**Connectivity & Security**
```
Sky VPC ──PrivateLink──► Snowflake (AWS region)
        ──IAM Role────► S3 (storage integration, no static keys)
        ──Secrets Mgr─► dbt / app credentials
Snowflake Network Policy: allow-list Sky VPC + GitHub Actions OIDC ranges
```

**CI/CD**
```
Developer ──PR──► GitHub
                  │
                  ├─ incoming_pr.yml  → snow dbt deploy/execute --target dev
                  │   (lint · compile · run · test on dev_schema)
                  │
                  └─ pr_merged.yml    → snow dbt deploy --target prod
                                        snow sql schedules.sql
Auth: GitHub OIDC → Snowflake service user (no static creds)
```

**Observability**
```
dbt runs / Lambda / Snowflake events
      │
      ├─ Logs   ──► Lambda forwarder ──► Splunk Cloud HEC
      │
      └─ Metrics ─► Grafana Cloud (Influx line protocol)
                   Alerts → on-call (Sky + Cognizant SRE)
```

**Identity & Access**
- **AWS:** IAM roles per environment (dev / preprod / prod), least-privilege S3 + KMS.
- **Snowflake:** functional roles (analyst, engineer) ↔ access roles (db.schema.priv); service users for CI and Lambda.
- **GitHub:** OIDC trust → Snowflake; no long-lived secrets in the repository.

### 2.4 Environment Topology

| Env | AWS account | Snowflake DB | dbt target | GitHub trigger |
|---|---|---|---|---|
| **dev** | sky-data-dev | `..._DB.dev_schema` | `dev` | PR open/update |
| **preprod** | sky-data-preprod | `..._DB.preprod_schema` | `preprod` | manual / release branch |
| **prod** | sky-data-prod | `..._DB.prod_schema` | `prod` | merge to `main` |

---

## 3. Migration Data Flow (End-to-End)

Path a single ETL job follows from BigQuery to Snowflake. The same pattern repeats for every job in scope (SOW §4.1.2 — Lift & Shift) and for history backfill (SOW §4.1.5).

### Stage 0 — Discovery & Schema Mapping *(one-time, per job)*

```
BigQuery dataset.table
     │
     ├─ INFORMATION_SCHEMA.COLUMNS  ─► extract DDL
     ├─ partitioning + clustering metadata
     └─ row counts, min/max of partition key  (for validation baseline)
                          │
                          ▼
       Snowflake Iceberg DDL (generated)
       - BQ types  → Snowflake types (e.g. INT64→NUMBER, STRING→VARCHAR)
       - BQ partition column → Iceberg partition spec
       - BQ clustering → Snowflake clustering keys
```

**Output:** `sources.yml` entry in dbt + an Iceberg `CREATE TABLE` script. This is the contract for the rest of the flow.

### Stage 1 — Export from BigQuery to GCS

```
BigQuery ──bq extract──► gs://sky-migration-staging/<job>/<date>/*.parquet
```

- **Format:** Parquet with SNAPPY compression (preserves types, splittable, Iceberg-friendly).
- **Partitioning:** export written into `dt=YYYY-MM-DD/` prefixes so downstream tools parallelise.
- **History vs. incremental:**
  - *History:* one-shot export of all partitions (could be TBs — run over a weekend window).
  - *Ongoing:* daily export of new partition only, until cutover.

### Stage 2 — Cross-Cloud Transfer GCS → S3

```
gs://sky-migration-staging   ───►   s3://sky-data-prod-raw/<job>/
        │
        ├─ Storage Transfer Service (Google-managed, scheduled)
        │   OR
        └─ AWS DataSync (AWS-managed, agent-based)
```

- Pick **one** based on egress cost & operational control.
- Encryption in flight: TLS. At rest: SSE-KMS with Sky's CMK.
- Checksum verified on landing (MD5/CRC32) — mismatch → object quarantined, job halts.

### Stage 3 — Land in S3 Raw Zone (Iceberg Layout)

```
s3://sky-data-prod-raw/<domain>/<job>/
   ├─ data/dt=2026-09-01/part-00000.parquet
   ├─ data/dt=2026-09-01/part-00001.parquet
   └─ metadata/                  ← Iceberg manifest + snapshot files
```

- **Iceberg** gives ACID snapshots, schema evolution, and time-travel on top of plain Parquet.
- The **metadata/** folder is what Snowflake registers against — not the Parquet files directly.
- S3 bucket policy: only the Snowflake storage-integration IAM role can read; only the loader role can write.

### Stage 4 — Register in Snowflake as an Iceberg Table

```sql
CREATE OR REPLACE ICEBERG TABLE raw.<job>
  EXTERNAL_VOLUME = 'sky_s3_raw'
  CATALOG = 'snowflake'
  BASE_LOCATION = '<domain>/<job>/'
  ;
```

- **No data copy** — Snowflake reads Parquet in-place from S3.
- Refreshing the table picks up new partitions written by Stage 2.
- This is the boundary where "AWS storage" becomes "queryable Snowflake".

### Stage 5 — dbt Transformation

```
sources.raw.<job>            ← Iceberg table (Stage 4)
       │
       ▼
staging.stg_<job>            ← type casts, renames, light cleanup
       │
       ▼
intermediate.int_<job>       ← business logic, joins
       │
       ▼
marts.<domain>_<entity>      ← serving table in prod_schema
```

- Same dbt code that ran against BigQuery, with macros to swap BQ-specific functions (`SAFE_CAST`, `STRUCT`, `UNNEST`) for Snowflake equivalents.
- Executed by the Snowflake CI/CD service user via OIDC.

### Stage 6 — Validation *(Milestone 1 Acceptance Gate)*

For the **one** ETL job selected for end-to-end validation:

| Check | BigQuery side | Snowflake side | Pass criterion |
|---|---|---|---|
| Row count | `SELECT COUNT(*)` | `SELECT COUNT(*)` | exact match |
| Distinct key count | `COUNT(DISTINCT pk)` | `COUNT(DISTINCT pk)` | exact match |
| Sum of numeric metric | `SUM(amount)` | `SUM(amount)` | within tolerance (e.g. ±0.01%) |
| Null distribution | `COUNT(*) WHERE col IS NULL` | same | exact match |
| Hash of sample rows | `farm_fingerprint` of N rows | hash of same N rows | exact match |

Failures → ticket, root-cause (export bug? type mismatch? dbt logic?) → re-run that stage only.

### Stage 7 — Observability Hooks *(across every stage)*

```
Stage 1 (bq extract)        ──► Cloud Logging   ─┐
Stage 2 (transfer)          ──► CloudWatch      ─┤
Stage 3 (S3 land)           ──► S3 events       ─┼─► Lambda forwarder
Stage 4 (Iceberg refresh)   ──► Snowflake events─┤        │
Stage 5 (dbt run)           ──► dbt artifacts ──┘        ▼
                                                    Splunk Cloud (logs)

Stage 5 (dbt run) ──► metrics (rows, duration, models) ──► Grafana Cloud
                                                          (Influx line protocol)
```

A single `run_id` flows through every stage — a row landing in Snowflake can be traced back to the BigQuery export it came from.

### Stage 8 — Cutover *(per job)*

```
Day N-7   ──► Run new pipeline in shadow mode, daily; validate against BQ each day
Day N-1   ──► Final history reconciliation; freeze BQ writes for this job
Day N     ──► Re-point downstream consumers from BQ to Snowflake
              (BI tools, reverse-ETL, APIs)
Day N+7   ──► BQ table marked read-only; kept for rollback window
Day N+30  ──► BQ table decommissioned (GCP cost stops)
```

Sky owns the cutover decision per job ("go-live decisions and GCP decommissioning rests with Sky" — SOW).

### 3.1 Shape to Remember

```
BigQuery ──► GCS ──► S3 ──► Iceberg ──► dbt ──► Snowflake marts ──► Consumers
   └────────── observability + validation runs alongside every hop ──────────┘
```

### 3.2 Failure Modes

| Failure | Stage | First signal |
|---|---|---|
| BQ export schema drift | 1 | Stage 0 DDL diff fails in CI |
| GCS→S3 transfer truncated | 2 | Checksum mismatch in CloudWatch |
| Wrong Parquet logical type | 3 | Iceberg refresh ok, dbt cast errors in Stage 5 |
| Snowflake can't read S3 | 4 | `SELECT` returns 0 rows or `403` |
| BQ-specific SQL function | 5 | dbt compile error in CI |
| Row-count mismatch | 6 | Validation gate blocks Milestone 1 sign-off |
| Silent metric drift | 6 | Sum-check fails — usually `SAFE_CAST` / NULL handling |

---

## 4. Milestone 1 — Environment Provisioning & Consumption Start

| Field | Value |
|---|---|
| **Target completion** | 30 September 2026 |
| **Phase** | Environment Provisioning |
| **Type** | Setup of Environment |
| **Sign-off** | Sky provides milestone completion sign within 10 business days |

### 4.1 Team (May → Sep, Cognizant)

| Role | May | Jun | Jul | Aug | Sep |
|---|---|---|---|---|---|
| SRE Engineer | 1 | 1 | 1 | 1 | 1 |
| SRE Senior Engineer | 1 | 1 | 1 | 1 | 1 |
| Senior Data Engineer | 1 | 1 | 2 | 2 | 1 |

### 4.2 Cognizant Deliverables (SOW)

- AWS account setup, RBAC policy configuration, secure data access
- Network Policies configuration
- CI/CD automation and pipeline setup
- DBT + GitHub environment configuration
- End-to-end validation of one ETL job on the new platform
- Ongoing SRE support

### 4.3 SRE Technical Workstream

| Area | Key activities |
|---|---|
| **AWS + Snowflake foundation** | VPC, IAM baseline, KMS, S3; Snowflake account, warehouses, RBAC model |
| **Secure data access** | PrivateLink, S3 storage integration, Secrets Manager, audit logging |
| **CI/CD automation** | GitHub repo, branch protections, dbt CI (compile/lint/test), container runner, OIDC to Snowflake |
| **dbt + GitHub env** | Project skeleton (sources/models/macros/tests), env-driven profiles, state in S3 |
| **Observability** | Splunk Cloud (logs via Lambda), Grafana Cloud (metrics via Influx), dashboards, alerts |
| **End-to-end validation** | One representative ETL job, prod-shaped data, parity checks vs. BigQuery |
| **Ongoing SRE support** | On-call rotation, runbooks, incident comms, teardown/rebuild path |

### 4.4 Suggested Sequencing

| Month | SRE focus |
|---|---|
| **May** | AWS landing zone, Snowflake account, IAM/RBAC scaffolding, repo + Dockerfile baseline |
| **Jun** | PrivateLink + storage integration, secrets, network policies, CI pipeline live |
| **Jul** | dbt environments (dev/preprod/prod), deploy pipeline, observability stack |
| **Aug** | One-ETL validation, dashboards/alerts, runbooks |
| **Sep** | Hardening, sign-off package, handover to ongoing SRE support |

---

## 5. Key Architectural Decisions

1. **Iceberg open tables** — Sky's data stays in open format on S3; avoids vendor lock-in; any engine can read the same files later.
2. **OIDC for CI** — no static Snowflake passwords in GitHub; short-lived tokens per workflow run.
3. **PrivateLink, not public endpoints** — Snowflake traffic stays on AWS backbone.
4. **dbt as the single transformation layer** — same tool BQ → Snowflake; minimises retraining; jobs lift-and-shift (SOW §4.1.2).
5. **Splunk + Grafana split** — logs to Splunk (Sky's existing SIEM), metrics to Grafana Cloud; no forced single pane.
6. **One-ETL acceptance gate** — Milestone 1 closes on *one validated job end-to-end*, not "all jobs migrated" — keeps scope honest.

---

## 6. Interview Talking Points *(quick reference)*

- **"Why Iceberg?"** → Open format, ACID on S3, no lock-in, future engines (Athena, Spark) can read the same data.
- **"Why not just copy data into Snowflake-native tables?"** → Would double-store TBs of data and bind Sky to Snowflake's format. Iceberg keeps the floor open.
- **"What's the riskiest part?"** → BigQuery-to-Snowflake SQL dialect gaps in dbt models (Stage 5). Mitigated by macro shims and parity tests at Stage 6.
- **"How do you know the migration is correct?"** → Stage 6 validation: row count, distinct key, sum-of-metric, null distribution, sample-row hash — all run automatically per job.
- **"How does Sky stay in control?"** → Sky owns cutover decisions per job (SOW), holds the CMK, owns the Snowflake account, and gets 10 business days to sign off each milestone.
- **"What does Milestone 1 actually prove?"** → That the *platform works end-to-end* for one job — not that the full migration is done. It's the smallest credible slice that exercises every layer.
- **"How is this different from a typical lift-and-shift?"** → Two things: (1) data lands in open Iceberg format, not Snowflake-proprietary; (2) the CI/CD + observability stack ships *with* the platform, not as a follow-on phase.

---

*Document version: 1.0 — for client review.*
