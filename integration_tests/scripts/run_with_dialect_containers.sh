#!/usr/bin/env bash
set -euo pipefail

INTEGRATION_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${INTEGRATION_TESTS_DIR}/docker-compose.dialect.yml"
COMPOSE_PROJECT="dbt-bigquery-federation-dialect"
POSTGRES_CONTAINER="dbt-bigquery-federation-dialect-postgres"
SPANNER_CONTAINER="dbt-bigquery-federation-spanner-emulator"
WAIT_SECONDS="${DIALECT_WAIT_TIMEOUT_SECONDS:-90}"

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Required command not found: $1" >&2
		exit 1
	fi
}

ensure_docker_prereqs() {
	require_command docker

	if ! docker info >/dev/null 2>&1; then
		echo "Docker is installed but the daemon is not reachable." >&2
		exit 1
	fi

	if ! docker compose version >/dev/null 2>&1; then
		echo "Docker Compose v2 is required for dialect extract tests." >&2
		exit 1
	fi
}

ensure_ports_available() {
	# If our dialect compose project already owns the ports, tear it down first
	# so a re-run does not false-fail on 5433/9010/9020.
	if docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" ps -q 2>/dev/null | grep -q .; then
		dialect_down
	fi

	if lsof -nP -iTCP:5433 -sTCP:LISTEN >/dev/null 2>&1; then
		echo "Port 5433 is already in use. Stop the existing listener or change the dialect Postgres host port." >&2
		exit 1
	fi
	if lsof -nP -iTCP:9010 -sTCP:LISTEN >/dev/null 2>&1; then
		echo "Port 9010 is already in use. Stop the existing Spanner emulator listener." >&2
		exit 1
	fi
}

dialect_up() {
	docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" up -d dialect-postgres spanner-emulator
}

dialect_logs() {
	docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" logs --no-color dialect-postgres spanner-emulator || true
}

dialect_down() {
	# Separate compose project from Jinja-engine Postgres; avoid --remove-orphans
	# so a sibling project's containers are never swept up by accident.
	docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" down >/dev/null 2>&1 || true
}

wait_healthy() {
	local container_name="$1"
	local started_at
	started_at="$(date +%s)"

	while true; do
		local state
		state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_name}" 2>/dev/null || true)"

		if [[ ${state} == "healthy" ]]; then
			return 0
		fi

		# Spanner emulator image has no Docker healthcheck; "running" is enough.
		if [[ ${container_name} == "${SPANNER_CONTAINER}" && ${state} == "running" ]]; then
			# Confirm gRPC port is accepting connections from the host.
			if (echo >/dev/tcp/127.0.0.1/9010) >/dev/null 2>&1; then
				return 0
			fi
		fi

		if [[ -z ${state} ]]; then
			echo "Container ${container_name} was not created successfully." >&2
			return 1
		fi

		now="$(date +%s)"
		if ((now - started_at >= WAIT_SECONDS)); then
			echo "Timed out waiting for ${container_name} after ${WAIT_SECONDS}s (state=${state})." >&2
			return 1
		fi

		sleep 1
	done
}

if [[ $# -eq 0 ]]; then
	echo "Usage: $0 <command> [args ...]" >&2
	exit 1
fi

ensure_docker_prereqs
ensure_ports_available
dialect_up

cleanup() {
	local exit_code="$1"
	if [[ ${exit_code} -ne 0 ]]; then
		dialect_logs
	fi
	dialect_down
	exit "${exit_code}"
}

trap 'cleanup $?' EXIT

wait_healthy "${POSTGRES_CONTAINER}"
wait_healthy "${SPANNER_CONTAINER}"
cd "${INTEGRATION_TESTS_DIR}"
"$@"
