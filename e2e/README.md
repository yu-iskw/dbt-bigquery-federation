# Local Google Cloud E2E

This directory provisions disposable Google Cloud resources for manually running real `EXTERNAL_QUERY` end-to-end tests from a developer machine. It intentionally does **not** add a GitHub Actions workflow that creates billable assets.

## Scope

The harness covers the two provider paths that cannot be validated by `bigquery-emulator`:

- AlloyDB for PostgreSQL -> BigQuery `EXTERNAL_QUERY`
- Spanner GoogleSQL -> BigQuery `EXTERNAL_QUERY`

Terraform owns infrastructure and BigQuery connection resources. SQL fixtures are committed separately so schema and row-level expectations stay reviewable. `run.sh` applies fixtures and executes live-discovery operations and representative federated queries.

### Type coverage (dual-layer)

Offline unit tests lock every package type-map entry (see `integration_tests/macros/tests/federation/test_postgres.sql` and `test_spanner_google.sql`).

Live e2e fixtures exercise federation under real connectors:

| Engine  | Fixture table        | Coverage                                                                                                                                                                                                                          |
| ------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AlloyDB | `public.type_matrix` | Google-documented EXTERNAL_QUERY-native PostgreSQL types from the package map, plus unsupported samples (`uuid`, `jsonb`, `inet`, `interval`) that require `safe` remote casts. Package-only natives such as `name` stay offline. |
| AlloyDB | `public.orders`      | Small smoke table (row-count check)                                                                                                                                                                                               |
| Spanner | `TypeMatrix`         | Every native scalar (`BOOL`, `BYTES`, `DATE`, `FLOAT64`, `INT64`, `JSON`, `NUMERIC`, `STRING`, `TIMESTAMP`) plus `ARRAY<STRING>`                                                                                                  |
| Spanner | `Orders`             | Small smoke table (row-count check)                                                                                                                                                                                               |

`assert_e2e_type_matrices` discovers live metadata, plans via `federated_relation(..., metadata_mode='live')`, and asserts planned actions plus federated cell values. Exotic unsupported Postgres types (geometry, `tsquery`, …) stay offline-only.

For Spanner, the Terraform module deliberately creates two BigQuery connections:

- a **parallel data connection** (`use_parallelism = true`) for representative table scans;
- a **non-parallel metadata connection** (`use_parallelism = false`) for `INFORMATION_SCHEMA` discovery.

Parallel Spanner connections are restricted to queries that satisfy Spanner's partitionability requirements. Metadata queries are not guaranteed to be root partitionable, so the package config uses the non-parallel connection as `metadata_connection_id` while ordinary table queries continue to use `connection_id`.

## Prerequisites

- Terraform >= 1.8
- Google Cloud SDK with Application Default Credentials (`gcloud auth application-default login`)
- `bq`, `psql`, and `alloydb-auth-proxy` on `PATH`
- a Google Cloud project with billing enabled
- permission to create AlloyDB, Spanner, BigQuery Connection, networking, and IAM resources

The AlloyDB fixture path uses a public IP **only through the AlloyDB Auth Proxy**. No authorized external network is configured. The local runner principal receives both `roles/alloydb.client` and `roles/serviceusage.serviceUsageConsumer`, which are required by the Auth Proxy. The BigQuery Connection service agent separately receives `roles/alloydb.client` so BigQuery can connect to AlloyDB.

Spanner uses a different authorization path: the local querying principal receives `roles/spanner.databaseReader` for federated reads and `roles/spanner.databaseUser` for fixture loading. The committed Spanner DML fixtures use `INSERT OR UPDATE`, so rerunning the local harness updates the same deterministic fixture rows rather than failing on duplicate primary keys.

**Note:** Adding `TypeMatrix` changes Spanner DDL. If you already applied an older stack, run `terraform destroy` then `terraform apply` (or recreate the Spanner database) before `./run.sh`.

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

1. seeds AlloyDB fixtures (`orders` + `type_matrix`) through `alloydb-auth-proxy`;
2. seeds Spanner fixture rows (`Orders` + `TypeMatrix`) with `gcloud spanner databases execute-sql`;
3. runs `dbt debug` against real BigQuery using OAuth/ADC;
4. calls `get_remote_columns` for AlloyDB `type_matrix` and Spanner `TypeMatrix`;
5. runs `assert_e2e_type_matrices` to verify live discovery, live `federated_relation` planning (including remote casts for unsupported AlloyDB types), and federated cell values;
6. executes representative `EXTERNAL_QUERY` statements with `bq query` against the smoke tables and checks deterministic row counts.

The existing credential-free emulator CI remains unchanged. Real Google Cloud provisioning and query execution are deliberately developer-triggered and are not performed by GitHub Actions.
