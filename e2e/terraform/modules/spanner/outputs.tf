output "bigquery_connection_id" {
  value = "projects/${var.project_id}/locations/${var.region}/connections/${google_bigquery_connection.spanner.connection_id}"
}

output "instance_id" {
  value = google_spanner_instance.this.name
}

output "database_id" {
  value = google_spanner_database.this.name
}
