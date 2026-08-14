data "google_project" "current" {
  project_id = var.project_id
}

locals {
  required_services = toset([
    "alloydb.googleapis.com",
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "spanner.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "bigquery_connection" {
  project = var.project_id
  service = "bigqueryconnection.googleapis.com"

  depends_on = [google_project_service.required]
}

module "alloydb" {
  source = "./modules/alloydb"

  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  runner_principal       = var.runner_principal
  bigquery_service_agent = google_project_service_identity.bigquery_connection.email

  depends_on = [google_project_service.required]
}

module "spanner" {
  source = "./modules/spanner"

  project_id       = var.project_id
  region           = var.region
  name_prefix      = var.name_prefix
  runner_principal = var.runner_principal

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "runner_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = var.runner_principal
}
