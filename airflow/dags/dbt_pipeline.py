"""
dbt_pipeline.py — Airflow DAG for dbt orchestration
====================================================
Replaces the dumb 'while true; sleep 60' loop in the dbt container
with a proper scheduled DAG that:
  1. Runs dbt run  (builds all models)
  2. Runs dbt test (validates data quality)
  3. Retries on failure with exponential backoff
  4. Keeps full execution history

This DAG runs every 5 minutes. In production you'd adjust the schedule
based on how fresh the data needs to be for your consumers.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

# =============================================================================
# DEFAULT ARGUMENTS
# Applied to every task in the DAG unless overridden at the task level.
# =============================================================================
default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    # If False: run even if the previous run failed.
    # If True: skip if previous run didn't succeed — useful for sequential jobs.
    "retries": 2,
    "retry_delay": timedelta(minutes=1),
    # Wait 1 minute before retrying a failed task.
    "retry_exponential_backoff": True,
    # Each retry waits longer: 1min, 2min, 4min...
    "email_on_failure": False,
    "email_on_retry": False,
}

# =============================================================================
# DAG DEFINITION
# =============================================================================
with DAG(
    dag_id="dbt_ecommerce_pipeline",
    description="Runs dbt models and tests for the CDC pipeline",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule="*/5 * * * *",
    # Cron expression: run every 5 minutes
    # */5 = every 5th minute, * = any hour/day/month/weekday
    catchup=False,
    # catchup=False: don't backfill missed runs since start_date.
    # With catchup=True, Airflow would try to run every missed 5-minute
    # slot since 2026-01-01 — that's thousands of runs on first deploy.
    tags=["dbt", "cdc", "ecommerce"],
) as dag:

    # -------------------------------------------------------------------------
    # Task 1: dbt run
    # Executes all models in dependency order (staging → marts).
    # BashOperator runs a shell command inside the Airflow worker container.
    # -------------------------------------------------------------------------
    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            "dbt run "
            "--profiles-dir /dbt "
            "--project-dir /dbt "
            "--no-partial-parse"
            # --no-partial-parse: always do a full parse.
            # Avoids stale cache issues in long-running containers.
        ),
    )

    # -------------------------------------------------------------------------
    # Task 2: dbt test
    # Runs all data quality tests defined in schema.yml.
    # Only runs if dbt_run succeeded — enforced by the >> operator below.
    # -------------------------------------------------------------------------
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            "dbt test "
            "--profiles-dir /dbt "
            "--project-dir /dbt "
            "--no-partial-parse"
        ),
    )

    # Define execution order: dbt_run must complete before dbt_test starts.
    # This is the DAG dependency graph — the core concept of Airflow.
    dbt_run >> dbt_test