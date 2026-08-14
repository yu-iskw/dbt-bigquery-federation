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
# adapter registration, package parsing, macro signatures, and model parsing
# without opening a BigQuery connection.
"${DBT_CMD}" parse --profiles-dir profiles --target "${TARGET}"

# dbt-bigquery's `dbt compile` opens a warehouse connection as part of
# materialization compilation, even when the selected federation models use
# pinned metadata only. A credential-free CI lane therefore cannot use
# `dbt compile` without conflating adapter compatibility with GCP auth.
#
# Instead, execute the pure pinned federation rendering contract through
# dbt-bigquery's Jinja/adapter context. This proves the package macros dispatch
# and render the expected EXTERNAL_QUERY SQL without touching the warehouse.
"${DBT_CMD}" run-operation test_federated_relation_renders_passthrough \
  --profiles-dir profiles \
  --target "${TARGET}"

# Exercise the public inspection path as another adapter-aware, warehouse-free
# operation. It must resolve the configured BigQuery connection resource and
# plan from pinned metadata only.
"${DBT_CMD}" run-operation federation_inspect \
  --profiles-dir profiles \
  --target "${TARGET}" \
  --args '{connection: application_pg, schema: public, table: orders}'
