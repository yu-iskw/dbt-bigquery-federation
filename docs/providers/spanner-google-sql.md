# Spanner GoogleSQL federation

`provider: spanner_google_sql` uses BigQuery `EXTERNAL_QUERY` against a Spanner GoogleSQL database. Spanner external datasets are intentionally out of scope.

The provider uses Spanner `INFORMATION_SCHEMA.COLUMNS` (`SPANNER_TYPE`) for live metadata discovery. Native mappings include BOOL, BYTES, DATE, FLOAT64, INT64, JSON, NUMERIC, STRING, TIMESTAMP, and ARRAY. STRUCT is not supported by BigQuery Spanner federation and is rejected unless a future explicit conversion policy is added.

Spanner TIMESTAMP values map to BigQuery TIMESTAMP with nanosecond precision truncated, so the planner reports `precision_loss`. Spanner NUMERIC is treated as native but carries a range-risk classification because values outside BigQuery NUMERIC's supported range can fail.

Connection configuration can set `options.query_execution_priority` to `high`, `medium`, or `low`; the option is rendered into `EXTERNAL_QUERY`. The default is left to BigQuery/Spanner (`medium`).

## Parallel reads and metadata discovery

A BigQuery Spanner connection can enable parallel reads with `use_parallelism`. Parallel connections can execute only queries that satisfy Spanner's partitionability requirements; otherwise BigQuery can return `Query is not root partitionable`.

`INFORMATION_SCHEMA` metadata queries are not guaranteed to be root partitionable. When the data connection enables parallel reads, configure a second Spanner connection with parallel reads disabled and set it as `metadata_connection_id`:

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      spanner_app:
        # May enable Spanner parallel reads for analytical table scans.
        connection_id: projects/my-project/locations/us-central1/connections/spanner_data

        # Keep this connection non-parallel for INFORMATION_SCHEMA discovery.
        metadata_connection_id: projects/my-project/locations/us-central1/connections/spanner_metadata

        provider: spanner_google_sql
        defaults:
          schema: ""
        types:
          policy: safe
```

Normal federated table queries continue to use `connection_id`; live schema discovery, pin generation, schema diff, and validation use `metadata_connection_id`.

`metadata_connection_id` is optional and defaults to `connection_id`. Therefore a single non-parallel Spanner connection remains sufficient when parallel reads aren't required.
