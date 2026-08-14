#!/usr/bin/env bash
set -euo pipefail

TARGET="bigquery"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

DBT_CMD="${DBT_CMD:-dbt}"

# Parse the full project using dbt-bigquery. This validates profile loading,
# adapter registration, package parsing, and macro signatures without touching GCP.
"${DBT_CMD}" parse --profiles-dir profiles --target "${TARGET}"

# Compile only pinned federation models. These exercise the real BigQuery adapter
# and BigQuery materialization context while deliberately avoiding live metadata
# discovery and warehouse access in credential-free CI.
"${DBT_CMD}" compile \
  --profiles-dir profiles \
  --target "${TARGET}" \
  --select stg_federated_orders stg_federated_orders_table

for model in stg_federated_orders stg_federated_orders_table; do
  compiled="target/compiled/dbt_bigquery_federation_integration_tests/models/federation/${model}.sql"
  test -f "${compiled}"
  grep -q "EXTERNAL_QUERY" "${compiled}"
  grep -q "projects/example/locations/us/connections/application-pg" "${compiled}"
done
