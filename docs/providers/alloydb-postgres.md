# AlloyDB PostgreSQL federation

`provider: alloydb_postgres` uses BigQuery `EXTERNAL_QUERY` against AlloyDB for PostgreSQL. It intentionally shares the PostgreSQL dialect, `information_schema.columns` metadata profile, and PostgreSQL-to-BigQuery type-planning profile with `cloud_sql_postgres`, while retaining a distinct provider identity and connection kind.

Live discovery, automatic planning, generated pins, schema diff, and validation therefore use the same logical PostgreSQL-family code path. Provider-specific Google Cloud IAM/networking and real federation execution belong in the authenticated GCP conformance layer; AlloyDB requires its own BigQuery connection and the connection service account must be able to access AlloyDB.
