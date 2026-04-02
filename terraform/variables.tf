# =============================================================================
# variables.tf — All configurable values for the CDC pipeline GCP deployment
# =============================================================================
# To use: create a terraform.tfvars file with your actual values.
# Never commit terraform.tfvars — it contains sensitive data.
# Example:
#   project_id = "my-gcp-project-123"
#   region     = "europe-west9"  # Paris region
# =============================================================================

variable "project_id" {
  description = "GCP project ID where all resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
  default     = "europe-west9"
  # europe-west9 = Paris — closest region to France, lowest latency
  # for French enterprise deployments. Also: europe-west1 = Belgium
}

variable "zone" {
  description = "GCP zone within the region"
  type        = string
  default     = "europe-west9-a"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "db_password" {
  description = "PostgreSQL database password for the ecommerce user"
  type        = string
  sensitive   = true
  # sensitive = true: Terraform will never print this value in logs or output
}

variable "db_tier" {
  description = "Cloud SQL instance machine tier"
  type        = string
  default     = "db-f1-micro"
  # db-f1-micro = smallest/cheapest tier, fine for dev
  # Production: db-custom-2-7680 (2 vCPU, 7.5GB RAM)
}

variable "gcs_bucket_name" {
  description = "Name of the GCS bucket for the data lake"
  type        = string
  # GCS bucket names must be globally unique across all of GCP
  # Convention: {project_id}-cdc-data-lake
}
