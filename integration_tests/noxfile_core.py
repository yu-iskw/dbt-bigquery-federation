"""Nox sessions for dbt Core and BigQuery emulator compatibility testing."""

import importlib.util
import os
from pathlib import Path

import nox

_root = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("nox_helpers", _root / "nox_helpers.py")
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"Cannot load nox_helpers from {_root / 'nox_helpers.py'}")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

from nox_helpers import (  # isort: skip  # noqa: E402
    ADAPTERS,
    build_env,
    get_dbt_command,
    install_dependencies,
    run_dbt_shell_script,
    run_deps,
)

PYTHON_VERSIONS = ["3.10", "3.11", "3.12"]
LOCAL_DBT_GROUPS = ["dbt-core-1-10", "dbt-core-1-11"]
SETUP_DBT_GROUPS = LOCAL_DBT_GROUPS
BIGQUERY_DBT_GROUPS = ["dbt-bigquery-1-10", "dbt-bigquery-1-11"]

nox.options.sessions = ["dev_unit_tests", "dev_integration_tests"]
nox.options.default_venv_backend = "uv"
nox.options.download_python = "auto"
nox.options.reuse_venv = "yes"


@nox.session(python="3.12")
def dev_unit_tests(session):
    unit_tests(session, "dbt-core-1-10", "postgres")


@nox.session(python="3.12")
def dev_integration_tests(session):
    integration_tests(session, "dbt-core-1-10", "postgres")


@nox.session(python=PYTHON_VERSIONS)
@nox.parametrize("uv_group", LOCAL_DBT_GROUPS)
@nox.parametrize("adapter", ADAPTERS)
def unit_tests(session, uv_group, adapter):
    run_dbt_shell_script(session, uv_group, adapter, "run_unit_tests.sh")


@nox.session(python=PYTHON_VERSIONS)
@nox.parametrize("uv_group", LOCAL_DBT_GROUPS)
@nox.parametrize("adapter", ADAPTERS)
def integration_tests(session, uv_group, adapter):
    run_dbt_shell_script(session, uv_group, adapter, "run_integration_tests.sh")


@nox.session(python=PYTHON_VERSIONS, tags=["ci"])
@nox.parametrize("uv_group", LOCAL_DBT_GROUPS)
@nox.parametrize("adapter", ADAPTERS)
def compatibility_tests(session, uv_group, adapter):
    """Run unit and integration tests for one isolated dbt Core environment."""
    unit_tests(session, uv_group, adapter)
    integration_tests(session, uv_group, adapter)


@nox.session(python="3.12", tags=["ci"])
@nox.parametrize("uv_group", BIGQUERY_DBT_GROUPS)
def bigquery_emulator_tests(session, uv_group):
    """Run dbt-bigquery compile checks against the local BigQuery emulator."""
    install_dependencies(session, uv_group)
    dbt_cmd = get_dbt_command(session, uv_group)
    env = build_env(session, uv_group, dbt_cmd)
    env.update(
        {
            "DBT_BIGQUERY_PROJECT": os.environ.get(
                "DBT_BIGQUERY_PROJECT", "dbt-bigquery-federation-ci"
            ),
            "DBT_BIGQUERY_DATASET": os.environ.get(
                "DBT_BIGQUERY_DATASET", "dbt_bigquery_federation_ci"
            ),
            "DBT_BIGQUERY_LOCATION": os.environ.get("DBT_BIGQUERY_LOCATION", "US"),
            "DBT_BIGQUERY_API_ENDPOINT": os.environ.get(
                "DBT_BIGQUERY_API_ENDPOINT", "http://127.0.0.1:9050"
            ),
        }
    )
    run_deps(session, dbt_cmd, "bigquery", env)
    session.run(
        "bash",
        "run_bigquery_compile_tests.sh",
        "--target",
        "bigquery",
        env=env,
        external=True,
    )


@nox.session(python=PYTHON_VERSIONS)
@nox.parametrize("uv_group", SETUP_DBT_GROUPS)
def setup_dbt_env(session, uv_group):
    install_dependencies(session, uv_group)
    dbt_cmd = get_dbt_command(session, uv_group)
    print(f"DBT_CMD={dbt_cmd}")
    print(f"BIN_PATH={session.bin}")
