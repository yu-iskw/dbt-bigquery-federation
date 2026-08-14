resource "random_password" "database" {
  length  = 32
  special = false
}

resource "google_compute_network" "alloydb" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-alloydb"
  auto_create_subnetworks = false
}

resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${var.name_prefix}-alloydb-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.alloydb.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.alloydb.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_alloydb_cluster" "this" {
  project    = var.project_id
  cluster_id = "${var.name_prefix}-cluster"
  location   = var.region

  network_config {
    network = google_compute_network.alloydb.id
  }

  initial_user {
    user     = "e2e_user"
    password = random_password.database.result
  }

  deletion_protection = false
  depends_on          = [google_service_networking_connection.private_vpc]
}

resource "google_alloydb_instance" "primary" {
  project       = var.project_id
  cluster       = google_alloydb_cluster.this.name
  instance_id   = "${var.name_prefix}-primary"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = 2
  }

  network_config {
    enable_public_ip = true
  }

  client_connection_config {
    require_connectors = true
  }
}

resource "google_project_iam_member" "runner_alloydb_client" {
  project = var.project_id
  role    = "roles/alloydb.client"
  member  = var.runner_principal
}

resource "google_project_iam_member" "connection_alloydb_client" {
  project = var.project_id
  role    = "roles/alloydb.client"
  member  = "serviceAccount:${var.bigquery_service_agent}"
}

resource "google_bigquery_connection" "alloydb" {
  project       = var.project_id
  location      = var.region
  connection_id = "${replace(var.name_prefix, "-", "_")}_alloydb"
  friendly_name = "dbt-bigquery-federation local E2E AlloyDB"

  configuration {
    connector_id = "google-alloydb"

    asset {
      database              = "postgres"
      google_cloud_resource = "//alloydb.googleapis.com/${google_alloydb_instance.primary.name}"
    }

    authentication {
      username_password {
        username = "e2e_user"
        password {
          plaintext = random_password.database.result
        }
      }
    }
  }

  depends_on = [google_project_iam_member.connection_alloydb_client]
}

resource "google_bigquery_connection_iam_member" "runner" {
  project       = var.project_id
  location      = google_bigquery_connection.alloydb.location
  connection_id = google_bigquery_connection.alloydb.connection_id
  role          = "roles/bigquery.connectionUser"
  member        = var.runner_principal
}
