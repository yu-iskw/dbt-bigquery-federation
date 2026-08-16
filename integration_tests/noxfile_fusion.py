"""Nox sessions for dbt Fusion compatibility testing."""

import importlib.util
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
    FUSION_GROUP,
    get_dbt_command,
    install_dependencies,
    run_dbt_shell_script,
)

FUSION_PYTHON = "3.12"
PYTHON_VERSIONS = ["3.10", "3.11", "3.12"]

nox.options.sessions = ["dev_unit_tests_fusion", "dev_integration_tests_fusion"]
nox.options.default_venv_backend = "uv"
nox.options.download_python = "auto"
nox.options.reuse_venv = "yes"


@nox.session(python=FUSION_PYTHON)
def dev_unit_tests_fusion(session):
    fusion_unit_tests(session)


@nox.session(python=FUSION_PYTHON)
def dev_integration_tests_fusion(session):
    fusion_integration_tests(session)


@nox.session(python=PYTHON_VERSIONS)
def fusion_unit_tests(session):
    for adapter in ADAPTERS:
        run_dbt_shell_script(session, FUSION_GROUP, adapter, "run_unit_tests.sh")


@nox.session(python=PYTHON_VERSIONS)
def fusion_integration_tests(session):
    for adapter in ADAPTERS:
        run_dbt_shell_script(session, FUSION_GROUP, adapter, "run_integration_tests.sh")


@nox.session(python=PYTHON_VERSIONS, tags=["ci"])
def compatibility_tests_fusion(session):
    """Run the complete Fusion suite in an isolated versioned environment."""
    fusion_unit_tests(session)
    fusion_integration_tests(session)


@nox.session(python=PYTHON_VERSIONS)
def setup_fusion_env(session):
    """Install dbt Fusion into the Nox virtual environment and print its path."""
    install_dependencies(session, FUSION_GROUP)
    dbt_cmd = get_dbt_command(session, FUSION_GROUP)
    print(f"DBT_CMD={dbt_cmd}")
    print(f"BIN_PATH={session.bin}")
