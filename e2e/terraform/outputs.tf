output "project_id" {
  value = var.project_id
}

output "bigquery_location" {
  value = var.region
}

output "alloydb_bigquery_connection_id" {
  value = module.alloydb.bigquery_connection_id
}

output "spanner_bigquery_connection_id" {
  description = "Backward-compatible alias for the parallel Spanner data connection."
  value       = module.spanner.bigquery_data_connection_id
}

output "spanner_data_bigquery_connection_id" {
  value = module.spanner.bigquery_data_connection_id
}

output "spanner_metadata_bigquery_connection_id" {
  value = module.spanner.bigquery_metadata_connection_id
}

output "alloydb_instance_uri" {
  value = module.alloydb.instance_uri
}

output "alloydb_database" {
  value = module.alloydb.database
}

output "alloydb_user" {
  value = module.alloydb.user
}

output "alloydb_password" {
  value     = module.alloydb.password
  sensitive = true
}

output "spanner_instance_id" {
  value = module.spanner.instance_id
}

output "spanner_database_id" {
  value = module.spanner.database_id
}
