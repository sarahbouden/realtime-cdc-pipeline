-- =============================================================================
-- E-Commerce Database Schema
-- Phase 1: Initial setup
-- 
-- This script runs once when the PostgreSQL container is first created.
-- It sets up the schema AND configures logical replication (required for CDC).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- LOGICAL REPLICATION SETUP
-- This is what makes CDC possible. We create a "publication" which tells
-- PostgreSQL: "make changes to these tables available for external consumers."
-- Debezium (Phase 2) will connect as a logical replication client and read
-- from this publication.
-- We define it here but it only becomes useful when Debezium connects.
-- -----------------------------------------------------------------------------
-- Note: wal_level=logical is set via docker-compose command, not here.
-- Publications are created after tables exist (see bottom of file).


-- -----------------------------------------------------------------------------
-- CUSTOMERS TABLE
-- Relatively static — inserts on registration, rare updates.
-- CDC on this table lets us track customer profile changes over time.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    id              SERIAL PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    country         VARCHAR(100) NOT NULL DEFAULT 'France',
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- PRODUCTS TABLE  
-- Product catalog. Price changes here are very interesting for analytics
-- (e.g., "did a price drop cause a spike in orders?").
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
    id              SERIAL PRIMARY KEY,
    sku             VARCHAR(100) NOT NULL UNIQUE,
    name            VARCHAR(255) NOT NULL,
    category        VARCHAR(100) NOT NULL,
    price           NUMERIC(10, 2) NOT NULL CHECK (price > 0),
    stock_quantity  INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- ORDERS TABLE
-- The core of our pipeline. This table changes constantly:
-- - New rows: customer places an order
-- - Updates: status transitions (pending → confirmed → shipped → delivered)
-- - Rare deletes: order cancellation cleanup
-- 
-- The 'status' column is what makes this table interesting for CDC —
-- every status change is a meaningful business event.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    id              SERIAL PRIMARY KEY,
    customer_id     INTEGER NOT NULL REFERENCES customers(id),
    product_id      INTEGER NOT NULL REFERENCES products(id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10, 2) NOT NULL CHECK (unit_price > 0),
    total_amount    NUMERIC(10, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    status          VARCHAR(50) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- INDEXES
-- Added for query performance on the columns we'll filter most.
-- In production, you'd add these after analyzing query patterns.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON orders(created_at);

-- -----------------------------------------------------------------------------
-- UPDATED_AT TRIGGER FUNCTION
-- Automatically sets updated_at = NOW() on every UPDATE.
-- This is a standard pattern for tracking when rows were last modified.
-- Without this, you'd have to remember to set it in every UPDATE query.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach the trigger to each table
CREATE TRIGGER trigger_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------------------------
-- LOGICAL REPLICATION PUBLICATION
-- This tells PostgreSQL to expose all changes on these three tables
-- to any logical replication consumer (Debezium in Phase 2).
-- 
-- We use FOR TABLE (explicit) rather than FOR ALL TABLES (too broad)
-- — a production best practice to avoid capturing system table noise.
-- -----------------------------------------------------------------------------
CREATE PUBLICATION ecommerce_publication 
    FOR TABLE customers, products, orders;

-- Confirm setup (visible in docker logs)
DO $$
BEGIN
    RAISE NOTICE '✓ Schema created: customers, products, orders';
    RAISE NOTICE '✓ Triggers created for updated_at';
    RAISE NOTICE '✓ Publication created: ecommerce_publication';
    RAISE NOTICE '✓ Database ready for CDC';
END $$;