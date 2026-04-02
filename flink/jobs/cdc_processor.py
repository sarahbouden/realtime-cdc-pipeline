"""
cdc_processor.py — Flink CDC Stream Processor
==============================================
Reads raw CDC events from Kafka, cleans and enriches them,
and writes processed records to JSON files for DuckDB to consume.

Architecture:
  Kafka (ecommerce.public.orders)
    → Flink Table API (filter, cast, enrich)
    → JSON sink (warehouse/orders/)

This job runs continuously — it never stops unless you stop it.
Every new Kafka message triggers processing within milliseconds.
"""

import os
import logging
from pyflink.datastream import StreamExecutionEnvironment, CheckpointingMode
from pyflink.table import StreamTableEnvironment, EnvironmentSettings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================
# StreamExecutionEnvironment is the entry point for all Flink jobs.
# It manages the job graph, checkpointing, and parallelism.
env = StreamExecutionEnvironment.get_execution_environment()

# Checkpointing: Flink saves state every 30 seconds.
# If the job crashes, it restarts from the last checkpoint — 
# guaranteeing no events are lost or double-processed.
env.enable_checkpointing(30000)  # 30 seconds in milliseconds
env.get_checkpoint_config().set_checkpointing_mode(CheckpointingMode.EXACTLY_ONCE)

# Parallelism: how many parallel instances of each operator to run.
# For local development, 1 is sufficient and easier to debug.
env.set_parallelism(1)

# TableEnvironment wraps the StreamEnvironment and adds SQL support.
# This is the Table API — we write SQL, Flink executes it as a stream.
settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
tbl_env = StreamTableEnvironment.create(env, environment_settings=settings)

# =============================================================================
# CONFIGURATION
# All connection details from environment variables — never hardcoded.
# =============================================================================
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_GROUP_ID  = os.getenv("KAFKA_GROUP_ID", "flink-cdc-processor")
WAREHOUSE_PATH  = os.getenv("WAREHOUSE_PATH", "/warehouse")

logger.info(f"Kafka bootstrap: {KAFKA_BOOTSTRAP}")
logger.info(f"Warehouse path:  {WAREHOUSE_PATH}")

# =============================================================================
# SOURCE TABLE — Kafka CDC Events
#
# We define a Flink Table that maps directly to the Kafka topic.
# Flink treats each Kafka message as a row in this table.
# The schema matches exactly what Debezium publishes after the
# ExtractNewRecordState transform unwraps the envelope.
# =============================================================================
tbl_env.execute_sql(f"""
    CREATE TABLE orders_raw (
        id             BIGINT,
        customer_id    BIGINT,
        product_id     BIGINT,
        quantity       INT,
        unit_price     DOUBLE,
        total_amount   DOUBLE,
        status         STRING,
        created_at     STRING,
        updated_at     STRING,
        `__op`         STRING,
        `__table`      STRING,
        `__ts_ms`      BIGINT,
        -- proc_time is a virtual column — Flink's processing timestamp.
        -- Used for windowed aggregations in later phases.
        proc_time      AS PROCTIME()
    ) WITH (
        'connector'                     = 'kafka',
        'topic'                         = 'ecommerce.public.orders',
        'properties.bootstrap.servers'  = '{KAFKA_BOOTSTRAP}',
        'properties.group.id'           = '{KAFKA_GROUP_ID}',
        'scan.startup.mode'             = 'earliest-offset',
        -- earliest-offset: read all messages including those already in Kafka
        -- (the snapshot events Debezium wrote before Flink started)
        'format'                        = 'json',
        'json.ignore-parse-errors'      = 'true'
        -- Ignore malformed messages instead of crashing the job
    )
""")

logger.info("✓ Source table 'orders_raw' created")

# =============================================================================
# SINK TABLE — Processed Orders (filesystem / DuckDB-ready)
#
# We write to JSON files that DuckDB can query directly in Phase 4.
# The filesystem connector writes files in a rolling fashion —
# it closes and rotates files based on time or size thresholds.
# =============================================================================
import os
os.makedirs(f"{WAREHOUSE_PATH}/orders_processed", exist_ok=True)

tbl_env.execute_sql(f"""
    CREATE TABLE orders_processed (
        id              BIGINT,
        customer_id     BIGINT,
        product_id      BIGINT,
        quantity        INT,
        unit_price      DOUBLE,
        total_amount    DOUBLE,
        status          STRING,
        operation       STRING,
        created_at      STRING,
        updated_at      STRING,
        processed_at    BIGINT
    ) WITH (
        'connector'         = 'filesystem',
        'path'              = '{WAREHOUSE_PATH}/orders_processed',
        'format'            = 'json',
        'sink.rolling-policy.rollover-interval'     = '60s',
        'sink.rolling-policy.check-interval'        = '10s'
        -- New output file created every 60 seconds.
        -- DuckDB will read all files in this directory in Phase 4.
    )
""")

logger.info("✓ Sink table 'orders_processed' created")

# =============================================================================
# TRANSFORMATION — The Core Logic
#
# This SQL runs continuously as a stream query:
# - Filters out snapshot events (__op = 'r') — we only want real changes
# - Maps operation codes to readable strings
# - Selects and renames columns for the clean output schema
# =============================================================================
result = tbl_env.execute_sql("""
    INSERT INTO orders_processed
    SELECT
        id,
        customer_id,
        product_id,
        quantity,
        unit_price,
        total_amount,
        status,
        CASE `__op`
            WHEN 'c' THEN 'INSERT'
            WHEN 'u' THEN 'UPDATE'
            WHEN 'd' THEN 'DELETE'
            ELSE 'UNKNOWN'
        END AS operation,
        created_at,
        updated_at,
        `__ts_ms` AS processed_at
    FROM orders_raw
    WHERE `__op` IN ('c', 'u', 'd')
    -- Filter: only process real changes, skip snapshot reads (__op = 'r')
    -- Snapshot data will be loaded separately by dbt in Phase 4
""")

logger.info("✓ Streaming job submitted — processing CDC events...")
logger.info("  Filtered operations: INSERT (c), UPDATE (u), DELETE (d)")
logger.info("  Skipping snapshot reads (__op = r)")

# result.wait() keeps the job running until manually stopped.
# Without this, the Python script exits and the job stops.
result.wait()