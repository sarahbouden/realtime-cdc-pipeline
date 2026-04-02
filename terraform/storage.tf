# =============================================================================
# storage.tf — GCS data lake bucket and BigQuery analytical warehouse
# =============================================================================
# GCS replaces our local warehouse/ volume.
# BigQuery replaces DuckDB for production-scale analytics.
# =============================================================================

# =============================================================================
# GCS BUCKET — Data Lake
# Stores raw Flink output (Parquet/JSON files), replacing warehouse/ volume.
# Organized with a folder structure that mirrors our local setup.
# =============================================================================

resource "google_storage_bucket" "data_lake" {
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = var.environment != "prod"
  # force_destroy = true in dev: allows 'terraform destroy' to delete
  # the bucket even if it contains files. NEVER true in production.

  # Versioning keeps previous versions of files for 30 days.
  # Essential for production: allows recovery from accidental overwrites.
  versioning {
    enabled = true
  }

  # Lifecycle rules automatically delete old files to control costs.
  lifecycle_rule {
    condition {
      age = 30
      # Delete files older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access: simpler and more secure than per-object ACLs
  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    project     = "cdc-pipeline"
    managed-by  = "terraform"
  }
}

# Pre-create the folder structure inside the bucket
# (GCS doesn't have real folders but placeholder objects create the structure)
resource "google_storage_bucket_object" "orders_folder" {
  name    = "orders_processed/.keep"
  bucket  = google_storage_bucket.data_lake.name
  content = "placeholder"
}

resource "google_storage_bucket_object" "checkpoints_folder" {
  name    = "flink_checkpoints/.keep"
  bucket  = google_storage_bucket.data_lake.name
  content = "placeholder"
}

# =============================================================================
# BIGQUERY — Analytical Warehouse
# Replaces DuckDB for production. BigQuery is serverless, scales to petabytes,
# and is the standard analytical warehouse in French GCP deployments.
# =============================================================================

resource "google_bigquery_dataset" "ecommerce" {
  dataset_id    = "ecommerce_${var.environment}"
  friendly_name = "E-Commerce CDC Pipeline — ${var.environment}"
  description   = "Analytical tables produced by the CDC pipeline dbt models"
  location      = var.region

  # Delete dataset only if empty (safety for production)
  delete_contents_on_destroy = var.environment != "prod"

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  depends_on = [google_project_service.bigquery]
}

# Define the BigQuery tables that dbt will populate.
# Terraform creates the schema; dbt fills in the data.
resource "google_bigquery_table" "fct_orders" {
  dataset_id          = google_bigquery_dataset.ecommerce.dataset_id
  table_id            = "fct_orders"
  deletion_protection = var.environment == "prod"
  # deletion_protection = true in prod: prevents accidental table deletion

  description = "Deduplicated orders fact table — latest state per order"

  schema = jsonencode([
    { name = "order_id",        type = "INT64",     mode = "REQUIRED" },
    { name = "customer_id",     type = "INT64",     mode = "REQUIRED" },
    { name = "product_id",      type = "INT64",     mode = "REQUIRED" },
    { name = "quantity",        type = "INT64",     mode = "REQUIRED" },
    { name = "unit_price",      type = "NUMERIC",   mode = "REQUIRED" },
    { name = "total_amount",    type = "NUMERIC",   mode = "REQUIRED" },
    { name = "status",          type = "STRING",    mode = "REQUIRED" },
    { name = "operation_type",  type = "STRING",    mode = "REQUIRED" },
    { name = "created_at",      type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "updated_at",      type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "processed_at",    type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_terminal_state", type = "BOOL",    mode = "NULLABLE" },
    { name = "created_hour",    type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "created_day",     type = "TIMESTAMP", mode = "NULLABLE" }
  ])

  # Partition by created_day for query cost optimization.
  # BigQuery charges per byte scanned — partitioning means queries
  # that filter by date only scan the relevant partitions.
  time_partitioning {
    type  = "DAY"
    field = "created_day"
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

resource "google_bigquery_table" "fct_order_metrics" {
  dataset_id          = google_bigquery_dataset.ecommerce.dataset_id
  table_id            = "fct_order_metrics"
  deletion_protection = var.environment == "prod"
  description         = "Hourly aggregated order KPIs"

  schema = jsonencode([
    { name = "metric_hour",           type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "total_orders",          type = "INT64",     mode = "NULLABLE" },
    { name = "pending_orders",        type = "INT64",     mode = "NULLABLE" },
    { name = "confirmed_orders",      type = "INT64",     mode = "NULLABLE" },
    { name = "shipped_orders",        type = "INT64",     mode = "NULLABLE" },
    { name = "delivered_orders",      type = "INT64",     mode = "NULLABLE" },
    { name = "cancelled_orders",      type = "INT64",     mode = "NULLABLE" },
    { name = "gross_revenue",         type = "NUMERIC",   mode = "NULLABLE" },
    { name = "net_revenue",           type = "NUMERIC",   mode = "NULLABLE" },
    { name = "avg_order_value",       type = "NUMERIC",   mode = "NULLABLE" },
    { name = "cancellation_rate_pct", type = "NUMERIC",   mode = "NULLABLE" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "metric_hour"
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}
