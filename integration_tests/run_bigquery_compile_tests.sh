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

# The profile routes dbt-bigquery's official google-cloud-bigquery client to
# bigquery-emulator using api_endpoint and a dummy OAuth bearer token. No ADC or
# Google Cloud project is required.
"${DBT_CMD}" debug --profiles-dir profiles --target "${TARGET}"
"${DBT_CMD}" parse --profiles-dir profiles --target "${TARGET}"

# Compile pinned federation models through the actual BigQuery adapter. This is
# the boundary that could not be exercised in credential-free CI before the
# emulator was introduced. The generated EXTERNAL_QUERY is not executed here;
# real federation remains the responsibility of authenticated GCP E2E tests.
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

test -f target/manifest.json
python - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("target/manifest.json").read_text())
macro_names = {node.get("name") for node in manifest.get("macros", {}).values()}
required = {
    "federated_relation",
    "external_query",
    "get_remote_columns",
    "federation_inspect",
    "federation_generate_pin",
    "federation_schema_diff",
    "federation_validate",
}
missing = sorted(required - macro_names)
if missing:
    raise SystemExit(f"Missing expected federation macros in manifest: {missing}")
PY
