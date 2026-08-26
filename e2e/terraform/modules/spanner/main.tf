resource "google_spanner_instance" "this" {
  project          = var.project_id
  name             = "${var.name_prefix}-spanner"
  display_name     = "dbt federation local E2E"
  config           = "regional-${var.region}"
  processing_units = 100
}

resource "google_spanner_database" "this" {
  # checkov:skip=CKV_GCP_119:Deletion protection is intentionally disabled for short-lived developer-created E2E resources so cleanup cannot strand billable infrastructure.
  # checkov:skip=CKV_GCP_120:Drop protection is intentionally disabled for this disposable E2E database so terraform destroy remains deterministic.
  # checkov:skip=CKV_GCP_93:Synthetic test data uses Google-managed encryption; requiring a persistent KMS key would undermine the disposable local E2E lifecycle.
  project  = var.project_id
  instance = google_spanner_instance.this.name
  name     = "e2e"

  ddl = [
    <<-SQL
    CREATE TABLE Orders (
      Id INT64 NOT NULL,
      Customer STRING(64) NOT NULL,
      Amount NUMERIC NOT NULL,
      Active BOOL NOT NULL,
      CreatedAt TIMESTAMP NOT NULL
    ) PRIMARY KEY (Id)
    SQL
    ,
    <<-SQL
    CREATE TABLE TypeMatrix (
      Id INT64 NOT NULL,
      ColBool BOOL NOT NULL,
      ColBytes BYTES(16) NOT NULL,
      ColDate DATE NOT NULL,
      ColFloat FLOAT64 NOT NULL,
      ColJson JSON NOT NULL,
      ColNumeric NUMERIC NOT NULL,
      ColString STRING(64) NOT NULL,
      ColTimestamp TIMESTAMP NOT NULL,
      ColArray ARRAY<STRING(16)>
    ) PRIMARY KEY (Id)
    SQL
  ]

  deletion_protection = false
}

# The data connection deliberately enables parallel reads. It represents the
# connection users may choose for root-partitionable analytical table scans.
resource "google_bigquery_connection" "spanner_data" {
  project       = var.project_id
  location      = var.region
  connection_id = "${replace(var.name_prefix, "-", "_")}_spanner"
  friendly_name = "dbt-bigquery-federation local E2E Spanner data"

  cloud_spanner {
    database        = google_spanner_database.this.id
    use_parallelism = true
  }
}

# INFORMATION_SCHEMA queries are not guaranteed to be root partitionable.
# Keep metadata discovery on a non-parallel connection so schema introspection
# does not fail with "Query is not root partitionable".
resource "google_bigquery_connection" "spanner_metadata" {
  project       = var.project_id
  location      = var.region
  connection_id = "${replace(var.name_prefix, "-", "_")}_spanner_metadata"
  friendly_name = "dbt-bigquery-federation local E2E Spanner metadata"

  cloud_spanner {
    database        = google_spanner_database.this.id
    use_parallelism = false
  }
}

resource "google_bigquery_connection_iam_member" "runner_data" {
  project       = var.project_id
  location      = google_bigquery_connection.spanner_data.location
  connection_id = google_bigquery_connection.spanner_data.connection_id
  role          = "roles/bigquery.connectionUser"
  member        = var.runner_principal
}

resource "google_bigquery_connection_iam_member" "runner_metadata" {
  project       = var.project_id
  location      = google_bigquery_connection.spanner_metadata.location
  connection_id = google_bigquery_connection.spanner_metadata.connection_id
  role          = "roles/bigquery.connectionUser"
  member        = var.runner_principal
}

# Spanner EXTERNAL_QUERY uses the querying principal's Spanner IAM when no
# fine-grained database role is configured on the connection.
resource "google_spanner_database_iam_member" "runner_reader" {
  project  = var.project_id
  instance = google_spanner_instance.this.name
  database = google_spanner_database.this.name
  role     = "roles/spanner.databaseReader"
  member   = var.runner_principal
}

# Fixture loading uses gcloud spanner databases execute-sql as the same local
# principal, so grant databaseUser in addition to the read-only query role.
resource "google_spanner_database_iam_member" "runner_writer" {
  project  = var.project_id
  instance = google_spanner_instance.this.name
  database = google_spanner_database.this.name
  role     = "roles/spanner.databaseUser"
  member   = var.runner_principal
}
