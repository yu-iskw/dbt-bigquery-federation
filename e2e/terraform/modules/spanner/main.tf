resource "google_spanner_instance" "this" {
  project      = var.project_id
  name         = "${var.name_prefix}-spanner"
  display_name = "dbt federation local E2E"
  config       = "regional-${var.region}"
  processing_units = 100
}

resource "google_spanner_database" "this" {
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
  ]

  deletion_protection = false
}

resource "google_bigquery_connection" "spanner" {
  project       = var.project_id
  location      = var.region
  connection_id = "${replace(var.name_prefix, "-", "_")}_spanner"
  friendly_name = "dbt-bigquery-federation local E2E Spanner"

  cloud_spanner {
    database = google_spanner_database.this.id
  }
}

resource "google_bigquery_connection_iam_member" "runner" {
  project       = var.project_id
  location      = google_bigquery_connection.spanner.location
  connection_id = google_bigquery_connection.spanner.connection_id
  role          = "roles/bigquery.connectionUser"
  member        = var.runner_principal
}

resource "google_spanner_database_iam_member" "runner_reader" {
  project  = var.project_id
  instance = google_spanner_instance.this.name
  database = google_spanner_database.this.name
  role     = "roles/spanner.databaseReader"
  member   = var.runner_principal
}

resource "google_spanner_database_iam_member" "runner_writer" {
  project  = var.project_id
  instance = google_spanner_instance.this.name
  database = google_spanner_database.this.name
  role     = "roles/spanner.databaseUser"
  member   = var.runner_principal
}
