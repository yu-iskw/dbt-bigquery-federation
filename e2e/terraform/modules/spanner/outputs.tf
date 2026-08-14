output "bigquery_connection_id" {
  description = "Backward-compatible alias for the parallel Spanner data connection."
  value       = "projects/${var.project_id}/locations/${var.region}/connections/${google_bigquery_connection.spanner_data.connection_id}"
}

output "bigquery_data_connection_id" {
  value = "projects/${var.project_id}/locations/${var.region}/connections/${google_bigquery_connection.spanner_data.connection_id}"
}

output "bigquery_metadata_connection_id" {
  value = "projects/${var.project_id}/locations/${var.region}/connections/${google_bigquery_connection.spanner_metadata.connection_id}"
}

output "instance_id" {
  value = google_spanner_instance.this.name
}

output "database_id" {
  value = google_spanner_database.this.name
}
