# =============================================================================
# Airflow Dockerfile
# Extends the official Airflow image with dbt-duckdb installed.
# We need dbt available inside the Airflow worker because BashOperator
# runs commands inside the Airflow container, not the dbt container.
# =============================================================================

FROM apache/airflow:2.9.1-python3.11

# Switch to root to install system packages
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user for pip installs
USER airflow

# Install dbt-duckdb so the DAG's BashOperator can run dbt commands
RUN pip install --no-cache-dir dbt-duckdb==1.8.1