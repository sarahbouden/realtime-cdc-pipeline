-- =============================================================================
-- fct_orders.sql — Orders fact table
-- =============================================================================
-- Contains the LATEST state of each order (deduplicated).
-- One row per order_id showing current status.
-- Materialized as TABLE for fast analytical queries.
-- =============================================================================

WITH staged AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

latest_per_order AS (
    SELECT
        order_id,
        MAX(processed_at) AS latest_processed_at
    FROM staged
    GROUP BY order_id
),

deduplicated AS (
    SELECT s.*
    FROM staged s
    INNER JOIN latest_per_order l
        ON  s.order_id = l.order_id
        AND s.processed_at = l.latest_processed_at
)

SELECT
    order_id,
    customer_id,
    product_id,
    quantity,
    unit_price,
    total_amount,
    status,
    operation_type,
    created_at,
    updated_at,
    processed_at,

    CASE status
        WHEN 'delivered' THEN true
        WHEN 'cancelled' THEN true
        ELSE false
    END AS is_terminal_state,

    DATE_TRUNC('hour', created_at) AS created_hour,
    DATE_TRUNC('day',  created_at) AS created_day

FROM deduplicated