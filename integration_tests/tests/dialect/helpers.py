"""Layer 3 dialect SQL helpers: dbt SQL export + dialect clients."""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from functools import lru_cache
from pathlib import Path
from typing import Any

import grpc

INTEGRATION_TESTS_DIR = Path(__file__).resolve().parents[2]
FIXTURES_DIR = INTEGRATION_TESTS_DIR / "fixtures" / "dialect"
TARGET_DIALECT_DIR = INTEGRATION_TESTS_DIR / "target" / "dialect"

DIALECT_PG_HOST = os.environ.get("DIALECT_POSTGRES_HOST", "127.0.0.1")
DIALECT_PG_PORT = int(os.environ.get("DIALECT_POSTGRES_PORT", "5433"))
DIALECT_PG_USER = os.environ.get("DIALECT_POSTGRES_USER", "postgres")
DIALECT_PG_PASSWORD = os.environ.get("DIALECT_POSTGRES_PASSWORD", "postgres")
DIALECT_PG_DATABASE = os.environ.get("DIALECT_POSTGRES_DATABASE", "federation_dialect")

SPANNER_PROJECT = os.environ.get("DIALECT_SPANNER_PROJECT", "dialect-test")
SPANNER_INSTANCE = os.environ.get("DIALECT_SPANNER_INSTANCE", "dialect-instance")
SPANNER_DATABASE = os.environ.get("DIALECT_SPANNER_DATABASE", "dialect-db")
SPANNER_EMULATOR_HOST = os.environ.get("SPANNER_EMULATOR_HOST", "localhost:9010")

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def _sql_statements(path: Path) -> list[str]:
    """Split a SQL file into statements, dropping full-line -- comments."""
    lines: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("--") or stripped == "":
            continue
        lines.append(line)
    text = "\n".join(lines)
    return [stmt.strip().rstrip(";") for stmt in text.split(";") if stmt.strip()]


def ensure_target_dir() -> Path:
    TARGET_DIALECT_DIR.mkdir(parents=True, exist_ok=True)
    return TARGET_DIALECT_DIR


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, default=str), encoding="utf-8")


def _strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def _parse_dialect_export(stdout: str) -> dict[str, Any] | None:
    """Parse DIALECT_EXPORT_JSON from dbt logs; optionally persist to DIALECT_EXPORT_PATH."""
    export_path: str | None = None
    export_json: str | None = None
    for raw in stdout.splitlines():
        line = _strip_ansi(raw)
        if "DIALECT_EXPORT_PATH=" in line:
            export_path = line.split("DIALECT_EXPORT_PATH=", 1)[1].strip()
        if "DIALECT_EXPORT_JSON=" in line:
            export_json = line.split("DIALECT_EXPORT_JSON=", 1)[1].strip()
    if export_json is None:
        return None
    payload = json.loads(export_json)
    if export_path is not None:
        write_json(Path(export_path), payload)
    return payload


def run_dbt_operation(
    macro: str, args: dict[str, Any], *, target: str = "duckdb"
) -> dict[str, Any]:
    """Invoke dbt run-operation; return parsed DIALECT_EXPORT JSON payload.

    Default target is duckdb: export/normalize macros do not call run_query, so the
    Jinja-engine Postgres container is unnecessary for Layer 3.
    """
    ensure_target_dir()
    dbt_cmd = os.environ.get("DBT_CMD", "dbt")
    cmd = [
        dbt_cmd,
        "run-operation",
        macro,
        "--args",
        json.dumps(args, default=str),
        "--profiles-dir",
        "profiles",
        "--target",
        target,
    ]
    completed = subprocess.run(
        cmd,
        cwd=INTEGRATION_TESTS_DIR,
        env=dict(os.environ),
        check=False,
        capture_output=True,
        text=True,
    )
    payload = _parse_dialect_export(completed.stdout)
    if completed.returncode != 0:
        raise AssertionError(
            f"dbt run-operation {macro} failed ({completed.returncode}):\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    if payload is None:
        raise AssertionError(
            f"dbt run-operation {macro} succeeded but emitted no DIALECT_EXPORT_JSON:\n"
            f"stdout:\n{completed.stdout}"
        )
    return payload


def lowercase_row_keys(row: dict[str, Any]) -> dict[str, Any]:
    return {str(k).lower(): v for k, v in row.items()}


def postgres_connect():
    import psycopg

    return psycopg.connect(
        host=DIALECT_PG_HOST,
        port=DIALECT_PG_PORT,
        user=DIALECT_PG_USER,
        password=DIALECT_PG_PASSWORD,
        dbname=DIALECT_PG_DATABASE,
    )


def seed_postgres() -> None:
    sql = (FIXTURES_DIR / "postgres_type_matrix.sql").read_text(encoding="utf-8")
    with postgres_connect() as conn:
        conn.execute(sql)
        conn.commit()


def postgres_fetch_dicts(sql: str) -> list[dict[str, Any]]:
    with postgres_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            columns = [desc.name for desc in cur.description]
            rows = cur.fetchall()
    return [lowercase_row_keys(dict(zip(columns, row, strict=True))) for row in rows]


def _spanner_admin_clients():
    """Admin clients on the local emulator via insecure gRPC.

    Newer google-cloud-spanner admin clients do not reliably honor
    SPANNER_EMULATOR_HOST alone; without an insecure channel they talk to
    production and hang or fail IAM checks.
    """
    from google.auth.credentials import AnonymousCredentials
    from google.cloud.spanner_admin_database_v1 import DatabaseAdminClient
    from google.cloud.spanner_admin_database_v1.services.database_admin.transports.grpc import (
        DatabaseAdminGrpcTransport,
    )
    from google.cloud.spanner_admin_instance_v1 import InstanceAdminClient
    from google.cloud.spanner_admin_instance_v1.services.instance_admin.transports.grpc import (
        InstanceAdminGrpcTransport,
    )

    os.environ.setdefault("SPANNER_EMULATOR_HOST", SPANNER_EMULATOR_HOST)
    creds = AnonymousCredentials()
    channel = grpc.insecure_channel(SPANNER_EMULATOR_HOST)
    instance_admin = InstanceAdminClient(
        transport=InstanceAdminGrpcTransport(channel=channel, credentials=creds)
    )
    database_admin = DatabaseAdminClient(
        transport=DatabaseAdminGrpcTransport(channel=channel, credentials=creds)
    )
    return instance_admin, database_admin, channel


@lru_cache(maxsize=1)
def _spanner_data_client():
    """Cached data client (honors SPANNER_EMULATOR_HOST for sessions/SQL)."""
    from google.auth.credentials import AnonymousCredentials
    from google.cloud import spanner

    os.environ.setdefault("SPANNER_EMULATOR_HOST", SPANNER_EMULATOR_HOST)
    return spanner.Client(project=SPANNER_PROJECT, credentials=AnonymousCredentials())


@lru_cache(maxsize=1)
def _spanner_database():
    return _spanner_data_client().instance(SPANNER_INSTANCE).database(SPANNER_DATABASE)


def seed_spanner() -> None:
    """Create emulator instance/database and apply DDL + DML."""
    from google.api_core import exceptions as gax_exceptions
    from google.cloud.spanner_admin_database_v1.types import spanner_database_admin
    from google.cloud.spanner_admin_instance_v1.types import spanner_instance_admin

    instance_admin, database_admin, _channel = _spanner_admin_clients()
    parent = f"projects/{SPANNER_PROJECT}"
    instance_id = SPANNER_INSTANCE
    instance_name = f"{parent}/instances/{instance_id}"

    try:
        instance_admin.get_instance(name=instance_name)
    except gax_exceptions.NotFound:
        op = instance_admin.create_instance(
            parent=parent,
            instance_id=instance_id,
            instance=spanner_instance_admin.Instance(
                name=instance_name,
                config=f"{parent}/instanceConfigs/emulator-config",
                display_name="dialect-test",
                node_count=1,
            ),
        )
        op.result(timeout=60)

    ddl_statements = _sql_statements(FIXTURES_DIR / "spanner_type_matrix_ddl.sql")
    db_name = f"{instance_name}/databases/{SPANNER_DATABASE}"
    try:
        database_admin.get_database(name=db_name)
        database_admin.drop_database(database=db_name)
    except gax_exceptions.NotFound:
        pass

    op = database_admin.create_database(
        request=spanner_database_admin.CreateDatabaseRequest(
            parent=instance_name,
            create_statement=f"CREATE DATABASE `{SPANNER_DATABASE}`",
            extra_statements=ddl_statements,
        )
    )
    op.result(timeout=60)

    _spanner_database.cache_clear()
    database = _spanner_database()
    dml_statements = _sql_statements(FIXTURES_DIR / "spanner_type_matrix_dml.sql")

    def _unit(transaction):
        for statement in dml_statements:
            transaction.execute_update(statement)

    database.run_in_transaction(_unit)


def spanner_fetch_dicts(sql: str) -> list[dict[str, Any]]:
    database = _spanner_database()
    with database.snapshot() as snapshot:
        result = snapshot.execute_sql(sql)
        raw_rows = list(result)
        columns = [field.name for field in result.fields]
    return [
        lowercase_row_keys(dict(zip(columns, list(row), strict=True)))
        for row in raw_rows
    ]
