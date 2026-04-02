-- =============================================================================
-- fct_order_metrics.sql — Hourly aggregated order KPIs
-- =============================================================================
-- Answers business questions like:
--   "How many orders were confirmed in the last hour?"
--   "What was the total revenue per hour?"
--   "What is the cancellation rate per hour?"
-- This table feeds Grafana dashboards in Phase 5.
-- =============================================================================

WITH orders AS (
    SELECT * FROM {{ ref('fct_orders') }}
),

hourly_metrics AS (
    SELECT
        created_hour                                AS metric_hour,

        COUNT(*)                                    AS total_orders,
        COUNT(CASE WHEN status = 'pending'
                   THEN 1 END)                      AS pending_orders,
        COUNT(CASE WHEN status = 'confirmed'
                   THEN 1 END)                      AS confirmed_orders,
        COUNT(CASE WHEN status = 'shipped'
                   THEN 1 END)                      AS shipped_orders,
        COUNT(CASE WHEN status = 'delivered'
                   THEN 1 END)                      AS delivered_orders,
        COUNT(CASE WHEN status = 'cancelled'
                   THEN 1 END)                      AS cancelled_orders,

        SUM(total_amount)                           AS gross_revenue,
        SUM(CASE WHEN status != 'cancelled'
                 THEN total_amount
                 ELSE 0 END)                        AS net_revenue,
        AVG(total_amount)                           AS avg_order_value,

        ROUND(
            100.0 * COUNT(CASE WHEN status = 'cancelled' THEN 1 END)
            / NULLIF(COUNT(*), 0),
            2
        )                                           AS cancellation_rate_pct

    FROM orders
    GROUP BY created_hour
)

SELECT
    metric_hour,
    total_orders,
    pending_orders,
    confirmed_orders,
    shipped_orders,
    delivered_orders,
    cancelled_orders,
    ROUND(gross_revenue,    2) AS gross_revenue,
    ROUND(net_revenue,      2) AS net_revenue,
    ROUND(avg_order_value,  2) AS avg_order_value,
    cancellation_rate_pct
FROM hourly_metrics
ORDER BY metric_hour DESC