# Local Google Cloud E2E

This directory provisions disposable Google Cloud resources for manually running real `EXTERNAL_QUERY` end-to-end tests from a developer machine. It intentionally does **not** add a GitHub Actions workflow that creates billable assets.

## Scope

The harness covers the two provider paths that cannot be validated by `bigquery-emulator`:

- AlloyDB for PostgreSQL -> BigQuery `EXTERNAL_QUERY`
- Spanner GoogleSQL -> BigQuery `EXTERNAL_QUERY`

Terraform owns infrastructure and BigQuery connection resources. SQL fixtures are committed separately so schema and row-level expectations stay reviewable. `run.sh` applies fixtures and executes live-discovery operations and representative federated queries.

## Prerequisites

- Terraform >= 1.8
- Google Cloud SDK with Application Default Credentials (`gcloud auth application-default login`)
- `bq`, `psql`, and `alloydb-auth-proxy` on `PATH`
- a Google Cloud project with billing enabled
- permission to create AlloyDB, Spanner, BigQuery Connection, networking, and IAM resources

The AlloyDB fixture path uses a public IP **only through the AlloyDB Auth Proxy**. No authorized external network is configured. The local runner principal receives both `roles/alloydb.client` and `roles/serviceusage.serviceUsageConsumer`, which are required by the Auth Proxy. The BigQuery Connection service agent separately receives `roles/alloydb.client` so BigQuery can connect to AlloyDB.

Spanner uses a different authorization path: the local querying principal receives `roles/spanner.databaseReader` for federated reads and `roles/spanner.databaseUser` for fixture loading. The committed Spanner DML fixture uses `INSERT OR UPDATE`, so rerunning the local harness updates the same deterministic fixture rows rather than failing on duplicate primary keys.

## Usage

```bash
cd e2e/terraform
cp terraform.tfvars.example terraform.tfvars
# edit project_id and runner_principal
terraform init
terraform apply

cd ..
./run.sh

# when finished
cd terraform
terraform destroy
```

`runner_principal` should be the IAM member used by local ADC, for example `user:you@example.com`. The harness grants only the roles needed to execute BigQuery jobs, use the test connections, seed/read the test Spanner database, and connect to the test AlloyDB instance.

## State and credentials

This harness is deliberately local and ephemeral. Terraform state contains generated database credentials because the BigQuery AlloyDB connection requires username/password authentication. Keep state local, never commit `terraform.tfstate*`, and destroy the stack after testing. For longer-lived environments, use a protected remote backend and a secret-management design instead of this local harness.

## What `run.sh` validates

1. seeds AlloyDB fixtures through `alloydb-auth-proxy`;
2. seeds Spanner fixture rows with `gcloud spanner databases execute-sql`;
3. runs `dbt debug` against real BigQuery using OAuth/ADC;
4. calls `get_remote_columns` for AlloyDB and Spanner to exercise live metadata discovery;
5. executes representative `EXTERNAL_QUERY` statements with `bq query` and checks deterministic row counts.

The existing credential-free emulator CI remains unchanged. Real Google Cloud provisioning and query execution are deliberately developer-triggered and are not performed by GitHub Actions.
