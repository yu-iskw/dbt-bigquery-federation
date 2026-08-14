# Spanner GoogleSQL federation

`provider: spanner_google_sql` uses BigQuery `EXTERNAL_QUERY` against a Spanner GoogleSQL database. Spanner external datasets are intentionally out of scope.

The provider uses Spanner `INFORMATION_SCHEMA.COLUMNS` (`SPANNER_TYPE`) for live metadata discovery. Native mappings include BOOL, BYTES, DATE, FLOAT64, INT64, JSON, NUMERIC, STRING, TIMESTAMP, and ARRAY. STRUCT is not supported by BigQuery Spanner federation and is rejected unless a future explicit conversion policy is added.

Spanner TIMESTAMP values map to BigQuery TIMESTAMP with nanosecond precision truncated, so the planner reports `precision_loss`. Spanner NUMERIC is treated as native but carries a range-risk classification because values outside BigQuery NUMERIC's supported range can fail.

Connection configuration can set `options.query_execution_priority` to `high`, `medium`, or `low`; the option is rendered into `EXTERNAL_QUERY`. The default is left to BigQuery/Spanner (`medium`).
