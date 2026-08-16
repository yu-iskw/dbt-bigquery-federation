#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}/integration_tests"

nox -f noxfile_core.py --tags ci "$@"
nox -f noxfile_fusion.py --tags ci "$@"
