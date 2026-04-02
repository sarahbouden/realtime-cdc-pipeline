-- =============================================================================
-- stg_orders.sql — Staging model for raw order CDC events
-- =============================================================================
-- Reads Flink output files from /warehouse/orders_processed/.
-- Flink names files as 'part-*' with no extension — we use a wildcard
-- glob and tell read_json_auto the format explicitly via 'format'.
-- =============================================================================

WITH raw_orders AS (

    SELECT *
    FROM read_json(
        '/warehouse/orders_processed/part-*',
        format = 'newline_delimited',
        -- Flink writes one JSON object per line (NDJSON format).
        -- read_json with format='newline_delimited' handles this correctly.
        -- read_json_auto would work too but requires a .json extension hint.
        ignore_errors = true,
        columns = {
            'id':           'BIGINT',
            'customer_id':  'BIGINT',
            'product_id':   'BIGINT',
            'quantity':     'INTEGER',
            'unit_price':   'DOUBLE',
            'total_amount': 'DOUBLE',
            'status':       'VARCHAR',
            'operation':    'VARCHAR',
            'created_at':   'VARCHAR',
            'updated_at':   'VARCHAR',
            'processed_at': 'BIGINT'
        }
        -- Explicit column types avoid schema inference errors when
        -- some files have null values that confuse the type guesser.
    )

)

SELECT
    CAST(id          AS BIGINT)          AS order_id,
    CAST(customer_id AS BIGINT)          AS customer_id,
    CAST(product_id  AS BIGINT)          AS product_id,
    CAST(quantity    AS INTEGER)         AS quantity,
    CAST(unit_price  AS DECIMAL(10, 2))  AS unit_price,
    -- total_amount is a PostgreSQL GENERATED column (quantity * unit_price).
    -- Debezium never includes generated column values in CDC payloads — they
    -- always arrive as null. We recompute it here from the two source fields,
    -- which ARE captured correctly by Debezium.
    CAST(quantity * unit_price AS DECIMAL(10, 2)) AS total_amount,
    LOWER(TRIM(status))                  AS status,
    UPPER(TRIM(operation))               AS operation_type,
    CAST(created_at  AS TIMESTAMP)       AS created_at,
    CAST(updated_at  AS TIMESTAMP)       AS updated_at,
    TO_TIMESTAMP(
        CAST(processed_at AS BIGINT) / 1000.0
    )                                    AS processed_at

FROM raw_orders
WHERE id IS NOT NULL
  AND customer_id IS NOT NULL
  AND product_id IS NOT NULL