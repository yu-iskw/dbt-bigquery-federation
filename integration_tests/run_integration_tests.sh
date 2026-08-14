#!/usr/bin/env bash
# Variables dbt_cmd, dbt_profiles_dir, dbt_target are set in scripts/dbt_harness.sh.
# shellcheck disable=SC1091,SC2154
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${ROOT}/scripts/dbt_harness.sh"

dbt_harness_parse_args "$@"
dbt_harness_cd

"${dbt_cmd}" deps --profiles-dir "${dbt_profiles_dir}" --target "${dbt_target}"
"${dbt_cmd}" build --profiles-dir "${dbt_profiles_dir}" \
  --target "${dbt_target}" \
  --exclude federation \
  --full-refresh
"${dbt_cmd}" compile --profiles-dir "${dbt_profiles_dir}" \
  --target "${dbt_target}" \
  --select federation

compiled_model="${ROOT}/target/compiled/dbt_bigquery_federation_integration_tests/models/federation/stg_federated_orders.sql"
if [[ ! -f "${compiled_model}" ]]; then
  echo "Expected compiled federated model at ${compiled_model}" >&2
  exit 1
fi
if ! grep -q "EXTERNAL_QUERY" "${compiled_model}"; then
  echo "Compiled federated model did not contain EXTERNAL_QUERY" >&2
  exit 1
fi
if grep -q "run_query" "${compiled_model}"; then
  echo "Compiled federated model unexpectedly contains run_query" >&2
  exit 1
fi
