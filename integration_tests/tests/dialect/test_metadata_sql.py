"""Suite A: provider metadata SQL against dialect engines + normalize to IR."""

from __future__ import annotations

from tests.dialect.helpers import (
    postgres_fetch_dicts,
    run_dbt_operation,
    spanner_fetch_dicts,
)


def test_postgres_metadata_sql_normalizes_to_ir(dialect_postgres_seeded):
    payload = run_dbt_operation(
        "dialect_export_metadata_remote_sql",
        {
            "provider": "cloud_sql_postgres",
            "schema": "public",
            "table": "type_matrix",
            "output_path": "target/dialect/pg_metadata_remote_sql.json",
        },
    )
    assert payload["ok"] is True
    assert "information_schema.columns" in payload["remote_sql"]

    rows = postgres_fetch_dicts(payload["remote_sql"])
    assert len(rows) >= 20
    assert rows[0]["column_name"] == "id"

    result = run_dbt_operation(
        "dialect_normalize_metadata_row_list",
        {
            "provider": "cloud_sql_postgres",
            "rows": rows,
            "fixture": "postgres_type_matrix",
            "output_path": "target/dialect/pg_normalize_result.json",
        },
    )
    assert result["ok"] is True
    assert result["matches_fixture"] is True


def test_spanner_metadata_sql_normalizes_to_ir(spanner_emulator_seeded):
    payload = run_dbt_operation(
        "dialect_export_metadata_remote_sql",
        {
            "provider": "spanner_google_sql",
            "schema": "",
            "table": "TypeMatrix",
            "output_path": "target/dialect/spanner_metadata_remote_sql.json",
        },
    )
    assert payload["ok"] is True
    assert "information_schema.columns" in payload["remote_sql"].lower()

    rows = spanner_fetch_dicts(payload["remote_sql"])
    assert len(rows) == 10
    assert rows[0]["column_name"] == "Id"

    result = run_dbt_operation(
        "dialect_normalize_metadata_row_list",
        {
            "provider": "spanner_google_sql",
            "rows": rows,
            "fixture": "spanner_type_matrix",
            "output_path": "target/dialect/spanner_normalize_result.json",
        },
    )
    assert result["ok"] is True
    assert result["matches_fixture"] is True
