# =============================================================================
# database.tf — Cloud SQL PostgreSQL instance
# =============================================================================
# Replaces our postgres Docker container with a managed PostgreSQL instance.
# Cloud SQL handles backups, patching, failover, and monitoring automatically.
# =============================================================================

resource "google_sql_database_instance" "postgres" {
  name             = "cdc-postgres-${var.environment}"
  database_version = "POSTGRES_16"
  region           = var.region

  deletion_protection = var.environment == "prod"
  # In prod: prevents accidental deletion via terraform destroy

  settings {
    tier = var.db_tier
    # db-f1-micro for dev, db-custom-2-7680 for prod

    # Enable logical replication — same as our wal_level=logical setting
    # This is required for Debezium CDC to work with Cloud SQL
    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "4"
    }

    database_flags {
      name  = "max_wal_senders"
      value = "4"
    }

    # Automated backups — retained for 7 days
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      # 3 AM UTC — low traffic window for French business hours
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
      }
    }

    # Maintenance window — Tuesday 4 AM UTC
    # Avoid Monday (post-weekend incidents) and Friday (pre-weekend risk)
    maintenance_window {
      day          = 2
      hour         = 4
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled    = false
      # No public IP — access only via private VPC
      # This is the security best practice for production databases
      private_network = google_compute_network.cdc_vpc.id
    }
  }

  depends_on = [
    google_project_service.sqladmin,
    google_compute_network.cdc_vpc
  ]
}

# Create the ecommerce database inside the instance
resource "google_sql_database" "ecommerce" {
  name     = "ecommerce"
  instance = google_sql_database_instance.postgres.name
}

# Create the application user
resource "google_sql_user" "ecommerce_user" {
  name     = "ecommerce_user"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
  # Password comes from variables — never hardcoded
}
