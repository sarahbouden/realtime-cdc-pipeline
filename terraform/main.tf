# =============================================================================
# main.tf — Provider configuration and project-level settings
# =============================================================================
# Terraform version constraints ensure reproducible deployments.
# Anyone running this code gets the same provider version.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
      # ~> 5.0 means: 5.x but not 6.x
      # Allows minor version updates but prevents breaking major version changes
    }
  }

  # Uncomment this block to store Terraform state in GCS instead of locally.
  # Remote state is required for team collaboration — without it, two people
  # running terraform apply simultaneously can corrupt infrastructure.
  #
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "cdc-pipeline/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  # Authentication: set GOOGLE_APPLICATION_CREDENTIALS env var to your
  # service account key JSON file path, or run 'gcloud auth application-default login'
}

# =============================================================================
# Enable required GCP APIs
# GCP requires explicitly enabling APIs before using them.
# These correspond to the services our pipeline uses.
# =============================================================================

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
  # disable_on_destroy = false: don't disable the API when we terraform destroy
  # Disabling APIs can break other resources in the project
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# Service Account for the CDC pipeline
# A service account is a non-human identity that our pipeline components
# use to authenticate with GCP APIs.
# Principle of least privilege: only grant the permissions actually needed.
# =============================================================================

resource "google_service_account" "cdc_pipeline" {
  account_id   = "cdc-pipeline-sa"
  display_name = "CDC Pipeline Service Account"
  description  = "Service account for the real-time CDC pipeline components"
}

# Grant the service account access to read/write GCS
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cdc_pipeline.email}"
}

# Grant access to write to BigQuery
resource "google_project_iam_member" "bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cdc_pipeline.email}"
}

# Grant access to publish/subscribe to Pub/Sub topics
resource "google_project_iam_member" "pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.cdc_pipeline.email}"
}
