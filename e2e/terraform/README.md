# Terraform stack

This stack is intentionally disposable and local-only. It creates the minimum real Google Cloud infrastructure needed to exercise AlloyDB and Spanner federation through BigQuery connections.

The root composes two focused modules:

- `modules/alloydb`: VPC/PSA, AlloyDB cluster + primary instance, database credentials, BigQuery AlloyDB connector, and IAM.
- `modules/spanner`: regional Spanner instance + database DDL, BigQuery Spanner connection, and IAM.

Do not commit generated state or `terraform.tfvars`. See `../README.md` for the full workflow.
