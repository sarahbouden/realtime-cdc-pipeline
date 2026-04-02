# =============================================================================
# outputs.tf — Values displayed after terraform apply
# =============================================================================
# Outputs serve two purposes:
#   1. Display useful information after deployment (connection strings, URLs)
#   2. Allow other Terraform modules to reference these values
# =============================================================================

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.cdc_vpc.name
}

output "subnet_cidr" {
  description = "CIDR range of the pipeline subnet"
  value       = google_compute_subnetwork.cdc_subnet.ip_cidr_range
}

output "postgres_connection_name" {
  description = "Cloud SQL connection name for use with Cloud SQL Auth Proxy"
  value       = google_sql_database_instance.postgres.connection_name
  # Format: project:region:instance-name
  # Used to connect via: cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432
}

output "postgres_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.private_ip_address
  sensitive   = false
}

output "gcs_bucket_url" {
  description = "GCS bucket URL for the data lake"
  value       = "gs://${google_storage_bucket.data_lake.name}"
}

output "bigquery_dataset" {
  description = "BigQuery dataset ID for dbt to target"
  value       = google_bigquery_dataset.ecommerce.dataset_id
}

output "service_account_email" {
  description = "Service account email for pipeline components"
  value       = google_service_account.cdc_pipeline.email
}

output "deployment_summary" {
  description = "Summary of all deployed resources"
  value = {
    environment      = var.environment
    region           = var.region
    database         = google_sql_database_instance.postgres.name
    data_lake        = "gs://${google_storage_bucket.data_lake.name}"
    warehouse        = "${var.project_id}.${google_bigquery_dataset.ecommerce.dataset_id}"
    service_account  = google_service_account.cdc_pipeline.email
  }
}
