# Terraform stack

This stack is intentionally disposable and local-only. It creates the minimum real Google Cloud infrastructure needed to exercise AlloyDB and Spanner federation through BigQuery connections.

The root composes two focused modules:

- `modules/alloydb`: VPC/PSA, AlloyDB cluster + primary instance, database credentials, BigQuery AlloyDB connector, and IAM.
- `modules/spanner`: regional Spanner instance + database DDL (`Orders` + `TypeMatrix`), a parallel BigQuery data connection, a non-parallel BigQuery metadata connection, and IAM.

The two Spanner connections intentionally exercise the package's connection split: normal `EXTERNAL_QUERY` table reads use the parallel data connection, while `INFORMATION_SCHEMA` discovery uses the non-parallel metadata connection so it isn't subject to root-partitionability requirements.

Do not commit generated state or `terraform.tfvars`. See `../README.md` for the full workflow.
