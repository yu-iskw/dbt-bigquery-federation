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

# Credential-free dbt-bigquery compatibility is intentionally limited to parse.
# Both `dbt compile` and `dbt run-operation` initialize a BigQuery connection and
# therefore require Application Default Credentials. Authenticated compilation,
# macro execution, live discovery, and federation execution belong in the GCP E2E
# suite instead of this always-on PR lane.
"${DBT_CMD}" parse --profiles-dir profiles --target "${TARGET}"

# Validate that parsing produced a manifest and that the package/public federation
# surface is present. This catches adapter installation/profile/macro parsing
# regressions without pretending to exercise warehouse-backed execution.
test -f target/manifest.json
python - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("target/manifest.json").read_text())
macros = manifest.get("macros", {})
macro_names = {node.get("name") for node in macros.values()}
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

models = manifest.get("nodes", {})
model_names = {
    node.get("name")
    for node in models.values()
    if node.get("resource_type") == "model"
}
required_models = {
    "stg_federated_orders",
    "stg_federated_orders_table",
    "stg_federated_orders_incremental",
}
missing_models = sorted(required_models - model_names)
if missing_models:
    raise SystemExit(f"Missing expected federation models in manifest: {missing_models}")
PY
