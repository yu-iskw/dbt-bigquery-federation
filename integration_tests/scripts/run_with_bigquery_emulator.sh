#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="dbt-bigquery-federation-emulator"
IMAGE="ghcr.io/goccy/bigquery-emulator:0.8.1"
PROJECT="${DBT_BIGQUERY_PROJECT:-dbt-bigquery-federation-ci}"
DATASET="${DBT_BIGQUERY_DATASET:-dbt_bigquery_federation_ci}"
WAIT_SECONDS="${BIGQUERY_EMULATOR_WAIT_TIMEOUT_SECONDS:-60}"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <command> [args ...]" >&2
  exit 1
fi

cleanup() {
  local exit_code="$?"
  if [[ "${exit_code}" -ne 0 ]]; then
    docker logs "${CONTAINER_NAME}" || true
  fi
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  exit "${exit_code}"
}
trap cleanup EXIT

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d --rm \
  --name "${CONTAINER_NAME}" \
  -p 9050:9050 \
  -p 9060:9060 \
  "${IMAGE}" \
  --project="${PROJECT}" \
  --dataset="${DATASET}" >/dev/null

started_at="$(date +%s)"
while ! curl --fail --silent \
  "http://127.0.0.1:9050/bigquery/v2/projects/${PROJECT}/datasets" >/dev/null; do
  now="$(date +%s)"
  if ((now - started_at >= WAIT_SECONDS)); then
    echo "Timed out waiting for BigQuery emulator after ${WAIT_SECONDS}s." >&2
    exit 1
  fi
  sleep 1
done

"$@"
