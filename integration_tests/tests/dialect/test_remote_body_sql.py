"""Suite B: planner remote_sql (EXTERNAL_QUERY body) executed on dialects."""

from __future__ import annotations

from tests.dialect.helpers import (
    postgres_fetch_dicts,
    run_dbt_operation,
    spanner_fetch_dicts,
)


def test_postgres_type_matrix_remote_sql_runs(dialect_postgres_seeded):
    payload = run_dbt_operation(
        "dialect_export_plan_remote_sql",
        {
            "fixture": "postgres_type_matrix",
            "output_path": "target/dialect/pg_plan_remote_sql.json",
        },
    )
    assert payload["ok"] is True
    assert payload["body"] == "projection"
    assert "cast(" in payload["remote_sql"].lower()
    assert "EXTERNAL_QUERY" not in payload["remote_sql"]

    rows = postgres_fetch_dicts(payload["remote_sql"])
    assert len(rows) == 1
    row = rows[0]
    assert row["id"] == 1
    assert row["col_text"] == "hello"
    assert str(row["col_uuid"]) == "11111111-1111-1111-1111-111111111111"
    assert "active" in str(row["col_jsonb"])


def test_postgres_orders_remote_sql_with_casts(dialect_postgres_seeded):
    payload = run_dbt_operation(
        "dialect_export_plan_remote_sql",
        {
            "fixture": "postgres_orders",
            "output_path": "target/dialect/pg_orders_remote_sql.json",
        },
    )
    assert payload["ok"] is True
    assert payload["body"] == "projection"
    rows = postgres_fetch_dicts(payload["remote_sql"])
    assert len(rows) == 2
    assert {r["id"] for r in rows} == {1, 2}


def test_spanner_type_matrix_passthrough_remote_sql(spanner_emulator_seeded):
    payload = run_dbt_operation(
        "dialect_export_plan_remote_sql",
        {
            "fixture": "spanner_type_matrix",
            "output_path": "target/dialect/spanner_plan_remote_sql.json",
        },
    )
    assert payload["ok"] is True
    assert payload["body"] == "passthrough"
    assert payload["remote_sql"].lower().replace("`", "") == "select * from typematrix"
    assert "EXTERNAL_QUERY" not in payload["remote_sql"]

    rows = spanner_fetch_dicts(payload["remote_sql"])
    assert len(rows) == 1
    row = rows[0]
    assert row["id"] == 1
    assert row["colstring"] == "alpha"
    assert row["colbool"] is True
