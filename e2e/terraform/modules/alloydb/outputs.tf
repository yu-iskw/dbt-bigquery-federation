output "bigquery_connection_id" {
  value = "projects/${var.project_id}/locations/${var.region}/connections/${google_bigquery_connection.alloydb.connection_id}"
}

output "instance_uri" {
  value = google_alloydb_instance.primary.name
}

output "database" {
  value = "postgres"
}

output "user" {
  value = "e2e_user"
}

output "password" {
  value     = random_password.database.result
  sensitive = true
}
