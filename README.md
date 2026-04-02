# Real-Time CDC Pipeline — E-Commerce Order Tracking

> A production-grade real-time data pipeline built with Change Data Capture (CDC), demonstrating end-to-end data engineering skills across ingestion, streaming, transformation, warehousing, orchestration, and cloud infrastructure.

---

## Business Case

In e-commerce, the operational database (PostgreSQL) handles thousands of transactions per minute. The analytics team needs real-time visibility into order trends, revenue, and cancellation rates — but cannot query the production database directly (too risky, too slow).

This pipeline solves that by automatically capturing every database change (INSERT, UPDATE, DELETE) and streaming it into an analytical warehouse in near real-time, keeping operational and analytical layers permanently synchronized without any impact on the source system.

---

## Architecture

```
PostgreSQL (WAL)
    │
    ▼
Debezium (CDC Connector)        captures row-level changes via logical replication
    │
    ▼
Apache Kafka                    durable event streaming backbone
    │
    ▼
Apache Flink                    real-time stream processing & transformation
    │
    ▼
DuckDB + dbt                    analytical warehouse + SQL models + data quality
    │
    ▼
Grafana                         live business dashboards
    │
Airflow                         orchestration & scheduling
    │
Terraform                       IaC for GCP cloud deployment
```

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Source DB | PostgreSQL | 16 |
| CDC Capture | Debezium | 2.6 |
| Event Streaming | Apache Kafka | 7.6 (Confluent) |
| Stream Processing | Apache Flink | 1.19 |
| Warehouse | DuckDB | 1.x |
| Transformation | dbt Core | 1.11 |
| Orchestration | Apache Airflow | 2.9 |
| Dashboards | Grafana | 10.4 |
| IaC | Terraform | >= 1.5 |
| Containerization | Docker Compose | v2 |
| Language | Python | 3.11 |

---

## Local Setup

### Prerequisites
- Docker Desktop 24+
- Docker Compose v2
- Git

### Run the Pipeline

```bash
# 1. Clone the repository
git clone https://github.com/sarahbouden/realtime-cdc-pipeline.git
cd realtime-cdc-pipeline

# 2. Create environment file
cp .env.example .env

# 3. Generate the Poetry lock file for the simulator
#    (only needed once — poetry.lock is committed so this is usually skipped)
cd simulator && poetry install && cd ..

# 4. Start all services (10 containers)
#    Docker builds the simulator image using Poetry internally
docker compose up --build

# 5. Register the Debezium CDC connector
bash scripts/register-debezium.sh

# 6. Submit the Flink streaming job
bash scripts/submit-flink-job.sh
```

> **Note:** No virtual environment setup needed. The simulator uses [Poetry](https://python-poetry.org/) for dependency management — Docker handles the Poetry install internally during image build. All other services run as pre-built Docker images.

### Verify the Pipeline

```bash
# Check CDC events flowing through Kafka
docker exec -it cdc_kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecommerce.public.orders \
  --from-beginning --max-messages 5

# Query the analytical warehouse
docker exec -it cdc_dbt python3 -c "
import duckdb
con = duckdb.connect('/warehouse/ecommerce.duckdb')
print(con.execute('SELECT status, COUNT(*) as orders, ROUND(SUM(total_amount),2) as revenue FROM fct_orders GROUP BY status ORDER BY orders DESC').df())
"
```

### Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Flink Web UI | http://localhost:8082 | — |
| Airflow | http://localhost:8080 | admin / (see logs) |
| Grafana | http://localhost:3000 | admin / admin |
| Kafka Connect | http://localhost:8083 | — |
| Schema Registry | http://localhost:8081 | — |
| Metrics API | http://localhost:3001 | — |

## Cloud Deployment (Terraform / GCP)

The `terraform/` directory contains production-ready IaC for GCP deployment:

- **Cloud SQL** (PostgreSQL 16 with logical replication)
- **GCS bucket** (data lake, replaces local warehouse/)
- **BigQuery** (analytical warehouse, replaces DuckDB)
- **VPC network** with private subnets and firewall rules
- **Service account** with least-privilege IAM roles

Target region: `europe-west9` (Paris) for GDPR compliance and low latency.

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan
```

---

## Author

**Sarra** — Data Science & AI Engineering Student (Bac+5)  
Mercedes-Benz Internship · Stuttgart/Sindelfingen, Germany  
Targeting: Lead Data Engineer / Head of Data roles in France
