variable "project_id" {
  description = "Google Cloud project used for disposable local E2E resources."
  type        = string
}

variable "region" {
  description = "Region for AlloyDB, Spanner regional configuration, and BigQuery connections."
  type        = string
  default     = "us-central1"
}

variable "runner_principal" {
  description = "IAM member used by local ADC, for example user:you@example.com."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for disposable E2E resource names."
  type        = string
  default     = "dbt-bq-fed-e2e"
}
