# Terraform — GCP Infrastructure for CDC Pipeline

This directory contains the Infrastructure-as-Code (IaC) configuration
to deploy the CDC pipeline on Google Cloud Platform.

## Architecture

```
GCP Project
├── VPC Network (europe-west9)
│   └── Subnet: 10.0.0.0/24
├── Cloud SQL (PostgreSQL 16)
│   ├── Logical replication enabled (for Debezium CDC)
│   ├── Private IP only (no public exposure)
│   └── Automated daily backups
├── GCS Bucket (Data Lake)
│   ├── orders_processed/   ← Flink output
│   └── flink_checkpoints/  ← Flink state
├── BigQuery Dataset
│   ├── fct_orders          ← dbt fact table
│   └── fct_order_metrics   ← dbt aggregations
└── Service Account
    └── Roles: Storage Admin, BigQuery Editor, Pub/Sub Editor
```

## Prerequisites

- Terraform >= 1.5.0
- GCP account with billing enabled
- `gcloud` CLI installed and authenticated

## Usage

```bash
# 1. Install Terraform
# https://developer.hashicorp.com/terraform/install

# 2. Authenticate with GCP
gcloud auth application-default login

# 3. Create your variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 4. Initialize Terraform (downloads providers)
terraform init

# 5. Preview what will be created
terraform plan

# 6. Deploy
terraform apply

# 7. Destroy when done (avoid ongoing costs)
terraform destroy
```

## Variables

Create `terraform.tfvars` (never commit this file):

```hcl
project_id      = "your-gcp-project-id"
region          = "europe-west9"
environment     = "dev"
db_password     = "your-secure-password"
gcs_bucket_name = "your-project-id-cdc-data-lake"
```

## Cost Estimate (dev environment)

| Resource       | Tier         | Estimated Cost |
|----------------|--------------|----------------|
| Cloud SQL      | db-f1-micro  | ~$10/month     |
| GCS Bucket     | Standard     | ~$0.02/GB/month|
| BigQuery       | On-demand    | $5/TB queried  |
| VPC Network    | -            | Free           |

**Destroy resources when not in use to avoid charges.**