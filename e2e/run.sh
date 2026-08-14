#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="${ROOT_DIR}/e2e"
TF_DIR="${E2E_DIR}/terraform"
INTEGRATION_DIR="${ROOT_DIR}/integration_tests"

for cmd in terraform gcloud bq psql alloydb-auth-proxy uv; do
  command -v "${cmd}" >/dev/null || { echo "missing required command: ${cmd}" >&2; exit 2; }
done

terraform -chdir="${TF_DIR}" output >/dev/null

PROJECT_ID="$(terraform -chdir="${TF_DIR}" output -raw project_id)"
BQ_LOCATION="$(terraform -chdir="${TF_DIR}" output -raw bigquery_location)"
ALLOYDB_CONNECTION_ID="$(terraform -chdir="${TF_DIR}" output -raw alloydb_bigquery_connection_id)"
SPANNER_CONNECTION_ID="$(terraform -chdir="${TF_DIR}" output -raw spanner_bigquery_connection_id)"
ALLOYDB_INSTANCE_URI="$(terraform -chdir="${TF_DIR}" output -raw alloydb_instance_uri)"
ALLOYDB_DATABASE="$(terraform -chdir="${TF_DIR}" output -raw alloydb_database)"
ALLOYDB_USER="$(terraform -chdir="${TF_DIR}" output -raw alloydb_user)"
ALLOYDB_PASSWORD="$(terraform -chdir="${TF_DIR}" output -raw alloydb_password)"
SPANNER_INSTANCE="$(terraform -chdir="${TF_DIR}" output -raw spanner_instance_id)"
SPANNER_DATABASE="$(terraform -chdir="${TF_DIR}" output -raw spanner_database_id)"

proxy_log="$(mktemp)"
alloydb-auth-proxy "${ALLOYDB_INSTANCE_URI}" --public-ip --port 55432 >"${proxy_log}" 2>&1 &
proxy_pid=$!
cleanup() {
  kill "${proxy_pid}" >/dev/null 2>&1 || true
  rm -f "${proxy_log}"
}
trap cleanup EXIT

for _ in {1..30}; do
  if PGPASSWORD="${ALLOYDB_PASSWORD}" psql -h 127.0.0.1 -p 55432 -U "${ALLOYDB_USER}" -d "${ALLOYDB_DATABASE}" -c 'select 1' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
PGPASSWORD="${ALLOYDB_PASSWORD}" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 55432 -U "${ALLOYDB_USER}" -d "${ALLOYDB_DATABASE}" -f "${E2E_DIR}/fixtures/alloydb.sql"

gcloud spanner databases execute-sql "${SPANNER_DATABASE}" \
  --instance="${SPANNER_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --sql="$(cat "${E2E_DIR}/fixtures/spanner.sql")"

export DBT_BIGQUERY_PROJECT="${PROJECT_ID}"
export DBT_BIGQUERY_DATASET="dbt_bigquery_federation_e2e"
export DBT_BIGQUERY_LOCATION="${BQ_LOCATION}"
export DBT_ALLOYDB_CONNECTION_ID="${ALLOYDB_CONNECTION_ID}"
export DBT_SPANNER_CONNECTION_ID="${SPANNER_CONNECTION_ID}"

cd "${INTEGRATION_DIR}"
uv run --group dbt-bigquery-1-11 dbt debug --profiles-dir profiles --target bigquery_gcp
uv run --group dbt-bigquery-1-11 dbt run-operation get_remote_columns --profiles-dir profiles --target bigquery_gcp \
  --args '{connection: analytics_alloydb, schema: public, table: orders}'
uv run --group dbt-bigquery-1-11 dbt run-operation get_remote_columns --profiles-dir profiles --target bigquery_gcp \
  --args '{connection: spanner_app, schema: "", table: Orders}'

alloydb_count="$(bq query --quiet --use_legacy_sql=false --format=csv --location="${BQ_LOCATION}" \
  "SELECT COUNT(*) AS row_count FROM EXTERNAL_QUERY('${ALLOYDB_CONNECTION_ID}', 'select * from public.orders')" | tail -n 1)"
spanner_count="$(bq query --quiet --use_legacy_sql=false --format=csv --location="${BQ_LOCATION}" \
  "SELECT COUNT(*) AS row_count FROM EXTERNAL_QUERY('${SPANNER_CONNECTION_ID}', 'select * from Orders')" | tail -n 1)"

[[ "${alloydb_count}" == "2" ]] || { echo "unexpected AlloyDB row count: ${alloydb_count}" >&2; exit 1; }
[[ "${spanner_count}" == "2" ]] || { echo "unexpected Spanner row count: ${spanner_count}" >&2; exit 1; }

echo "Local real-GCP E2E passed: AlloyDB=${alloydb_count}, Spanner=${spanner_count}"
