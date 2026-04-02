# =============================================================================
# dbt Dockerfile — dbt Core with DuckDB adapter
# =============================================================================

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir dbt-duckdb==1.8.1 duckdb

WORKDIR /dbt

COPY . .

# run.sh: runs dbt every 60 seconds and exports results as JSON for Grafana
RUN printf '#!/bin/bash\n\
echo "dbt runner starting..."\n\
while true; do\n\
    echo "-- dbt run $(date) --"\n\
    dbt run --profiles-dir /dbt --project-dir /dbt --no-partial-parse\n\
    echo "-- dbt test $(date) --"\n\
    dbt test --profiles-dir /dbt --project-dir /dbt --no-partial-parse\n\
    echo "-- Exporting metrics for Grafana --"\n\
    python3 /dbt/export_metrics.py\n\
    echo "-- Sleeping 60s --"\n\
    sleep 60\n\
done\n' > /dbt/run.sh && chmod +x /dbt/run.sh

CMD ["/dbt/run.sh"]