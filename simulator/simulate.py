"""
simulate.py — E-Commerce Order Activity Simulator
==================================================
Continuously generates realistic INSERT and UPDATE activity
on the PostgreSQL orders database.

Business logic simulated:
- New customers register (slow rate)
- New orders are placed continuously  
- Orders progress through status lifecycle
- Some orders get cancelled

This gives our CDC pipeline a constant stream of real changes to capture.
"""

import os
import sys
import time
import random
import logging
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor
from faker import Faker
from dotenv import load_dotenv

# =============================================================================
# LOGGING SETUP
# We use structured logging so outputs are easy to parse and monitor.
# Format: timestamp | level | message
# In production, you'd ship these logs to a log aggregator (Datadog, ELK, etc.)
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# =============================================================================
# CONFIGURATION
# All values come from environment variables (set via .env file).
# Never hardcode connection strings or passwords in code.
# =============================================================================
load_dotenv()

DB_CONFIG = {
    "host":     os.environ["POSTGRES_HOST"],
    "port":     int(os.environ["POSTGRES_PORT"]),
    "dbname":   os.environ["POSTGRES_DB"],
    "user":     os.environ["POSTGRES_USER"],
    "password": os.environ["POSTGRES_PASSWORD"],
}

ORDERS_PER_CYCLE   = int(os.getenv("SIMULATOR_ORDERS_PER_CYCLE", 5))
CYCLE_SECONDS      = int(os.getenv("SIMULATOR_CYCLE_SECONDS", 3))
SEED_CUSTOMERS     = int(os.getenv("SIMULATOR_SEED_CUSTOMERS", 50))
SEED_PRODUCTS      = int(os.getenv("SIMULATOR_SEED_PRODUCTS", 20))

# Order status lifecycle — a new order always starts as 'pending'
# and can only move forward (or be cancelled)
STATUS_TRANSITIONS = {
    "pending":   ["confirmed", "cancelled"],
    "confirmed": ["shipped",   "cancelled"],
    "shipped":   ["delivered"],
    "delivered": [],   # terminal state
    "cancelled": [],   # terminal state
}

# Probability that an order gets cancelled at each eligible transition
CANCELLATION_RATE = 0.10  # 10%

fake = Faker("fr_FR")  # French locale for realistic names/addresses


# =============================================================================
# DATABASE CONNECTION
# We use a retry loop because when Docker Compose starts, the simulator
# container may be ready before PostgreSQL finishes its own initialization.
# This is called "startup ordering" — a common Docker Compose challenge.
# =============================================================================
def get_connection(retries: int = 10, delay: int = 3) -> psycopg2.extensions.connection:
    """
    Attempt to connect to PostgreSQL with retries.
    
    Why retries? In Docker Compose, all containers start roughly simultaneously.
    PostgreSQL takes ~5-10 seconds to fully initialize. Without retries,
    the simulator would crash immediately with 'Connection refused'.
    """
    for attempt in range(1, retries + 1):
        try:
            conn = psycopg2.connect(**DB_CONFIG)
            conn.autocommit = False  # We manage transactions explicitly
            logger.info(f"✓ Connected to PostgreSQL (attempt {attempt}/{retries})")
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"PostgreSQL not ready yet (attempt {attempt}/{retries}): {e}")
            if attempt < retries:
                time.sleep(delay)
            else:
                logger.error("Could not connect to PostgreSQL after all retries. Exiting.")
                sys.exit(1)


# =============================================================================
# SEED DATA
# On first startup, populate customers and products tables.
# Idempotent: uses INSERT ... ON CONFLICT DO NOTHING so re-running is safe.
# =============================================================================
def seed_customers(conn: psycopg2.extensions.connection, count: int) -> None:
    """Insert realistic customer records if they don't already exist."""
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM customers")
        existing = cur.fetchone()[0]
        
        if existing >= count:
            logger.info(f"✓ Customers already seeded ({existing} records found)")
            return

        logger.info(f"Seeding {count} customers...")
        inserted = 0
        for _ in range(count):
            try:
                cur.execute(
                    """
                    INSERT INTO customers (email, first_name, last_name, country)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (email) DO NOTHING
                    """,
                    (
                        fake.unique.email(),
                        fake.first_name(),
                        fake.last_name(),
                        random.choice(["France", "Belgique", "Suisse", "Canada"]),
                    ),
                )
                inserted += cur.rowcount
            except Exception as e:
                logger.warning(f"Skipped duplicate customer: {e}")
                conn.rollback()
                continue
        
        conn.commit()
        logger.info(f"✓ Seeded {inserted} customers")


def seed_products(conn: psycopg2.extensions.connection, count: int) -> None:
    """Insert realistic product records if they don't already exist."""
    
    # Realistic product catalog for a French e-commerce site
    product_templates = [
        ("Smartphone Samsung Galaxy A54", "Électronique",  299.99),
        ("Laptop Lenovo ThinkPad E15",   "Informatique",  799.00),
        ("Casque Sony WH-1000XM5",       "Électronique",  349.00),
        ("Montre Garmin Forerunner 255", "Sport",         349.99),
        ("Livre 'Le Petit Prince'",      "Livres",          8.90),
        ("Cafetière Nespresso Vertuo",   "Maison",        149.00),
        ("Vélo électrique Urban Glide",  "Sport",        1299.00),
        ("Chaise bureau ergonomique",    "Maison",        299.00),
        ("Airpods Pro 2ème génération",  "Électronique",  279.00),
        ("Tablette iPad 10ème gen",      "Informatique",  589.00),
        ("Nike Air Max 90",              "Mode",          130.00),
        ("Parfum Chanel N°5 50ml",       "Beauté",        120.00),
        ("Robot aspirateur Roomba j7",   "Maison",        599.00),
        ("Jeu PS5 Spider-Man 2",         "Jeux vidéo",     79.99),
        ("Enceinte JBL Charge 5",        "Électronique",  179.00),
        ("Trottinette électrique Xiaomi","Sport",         399.00),
        ("Machine à café DeLonghi",      "Maison",        249.00),
        ("Sac à dos Eastpak 30L",        "Mode",           65.00),
        ("Kindle Paperwhite 11ème gen",  "Informatique",  149.99),
        ("Console Nintendo Switch OLED", "Jeux vidéo",    349.99),
    ]

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM products")
        existing = cur.fetchone()[0]

        if existing >= count:
            logger.info(f"✓ Products already seeded ({existing} records found)")
            return

        logger.info(f"Seeding {count} products...")
        inserted = 0
        for i, (name, category, price) in enumerate(product_templates[:count]):
            sku = f"SKU-{category[:3].upper()}-{i+1:04d}"
            cur.execute(
                """
                INSERT INTO products (sku, name, category, price, stock_quantity)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (sku) DO NOTHING
                """,
                (sku, name, category, price, random.randint(10, 500)),
            )
            inserted += cur.rowcount

        conn.commit()
        logger.info(f"✓ Seeded {inserted} products")


# =============================================================================
# SIMULATION ACTIONS
# Each function represents one type of business event.
# =============================================================================
def create_order(conn: psycopg2.extensions.connection) -> int | None:
    """
    Simulate a customer placing a new order.
    Returns the new order ID, or None if insertion failed.
    """
    with conn.cursor() as cur:
        # Pick a random customer and product
        cur.execute("SELECT id FROM customers ORDER BY RANDOM() LIMIT 1")
        customer = cur.fetchone()

        cur.execute("SELECT id, price FROM products ORDER BY RANDOM() LIMIT 1")
        product = cur.fetchone()

        if not customer or not product:
            logger.warning("No customers or products found — skipping order creation")
            return None

        customer_id = customer[0]
        product_id, unit_price = product[0], product[1]
        quantity = random.randint(1, 5)

        cur.execute(
            """
            INSERT INTO orders (customer_id, product_id, quantity, unit_price, status)
            VALUES (%s, %s, %s, %s, 'pending')
            RETURNING id, total_amount
            """,
            (customer_id, product_id, quantity, unit_price),
        )
        row = cur.fetchone()
        conn.commit()

        order_id, total = row[0], row[1]
        logger.info(
            f"  [CREATE] Order #{order_id} | customer={customer_id} "
            f"product={product_id} qty={quantity} total=€{total:.2f}"
        )
        return order_id


def advance_order_status(conn: psycopg2.extensions.connection) -> None:
    """
    Pick a random non-terminal order and advance its status.
    This generates the UPDATE events that are the core of our CDC stream.
    """
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # Find orders that can still transition (not delivered/cancelled)
        cur.execute(
            """
            SELECT id, status 
            FROM orders 
            WHERE status NOT IN ('delivered', 'cancelled')
            ORDER BY RANDOM()
            LIMIT 1
            """
        )
        order = cur.fetchone()

        if not order:
            logger.debug("No orders available for status advancement")
            return

        order_id = order["id"]
        current_status = order["status"]
        possible_next = STATUS_TRANSITIONS.get(current_status, [])

        if not possible_next:
            return

        # Apply cancellation rate logic
        if "cancelled" in possible_next and random.random() < CANCELLATION_RATE:
            next_status = "cancelled"
        else:
            # Choose a non-cancelled next status if available
            non_cancel = [s for s in possible_next if s != "cancelled"]
            next_status = random.choice(non_cancel) if non_cancel else "cancelled"

        cur.execute(
            "UPDATE orders SET status = %s WHERE id = %s",
            (next_status, order_id),
        )
        conn.commit()

        emoji = "❌" if next_status == "cancelled" else "→"
        logger.info(
            f"  [UPDATE] Order #{order_id} | "
            f"{current_status} {emoji} {next_status}"
        )


def get_pipeline_stats(conn: psycopg2.extensions.connection) -> None:
    """
    Log a summary of current order distribution.
    Helps us verify the simulator is working correctly.
    """
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT 
                status,
                COUNT(*)           AS count,
                SUM(total_amount)  AS revenue
            FROM orders
            GROUP BY status
            ORDER BY count DESC
            """
        )
        rows = cur.fetchall()
        if rows:
            logger.info("  ── Pipeline Stats ──────────────────────────")
            for row in rows:
                revenue = float(row["revenue"] or 0)
                logger.info(
                    f"  {row['status']:12s} | {row['count']:5d} orders | "
                    f"€{revenue:,.2f}"
                )
            logger.info("  ────────────────────────────────────────────")


# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================
def run_simulation() -> None:
    """
    Main entry point. Connects to DB, seeds data, then loops forever
    generating realistic order activity.
    """
    logger.info("=" * 60)
    logger.info("  E-Commerce CDC Simulator — Starting")
    logger.info("=" * 60)
    logger.info(f"  Orders per cycle : {ORDERS_PER_CYCLE}")
    logger.info(f"  Cycle interval   : {CYCLE_SECONDS}s")
    logger.info("=" * 60)

    conn = get_connection()

    # One-time setup: populate reference data
    seed_customers(conn, SEED_CUSTOMERS)
    seed_products(conn, SEED_PRODUCTS)

    cycle = 0
    while True:
        cycle += 1
        logger.info(f"── Cycle #{cycle} ──────────────────────────────────────")

        try:
            # Create new orders
            for _ in range(ORDERS_PER_CYCLE):
                create_order(conn)

            # Advance 2-4 existing orders (more updates than inserts is realistic)
            updates = random.randint(2, 4)
            for _ in range(updates):
                advance_order_status(conn)

            # Every 10 cycles, print a stats summary
            if cycle % 10 == 0:
                get_pipeline_stats(conn)

        except psycopg2.OperationalError as e:
            # Connection dropped — try to reconnect
            logger.error(f"Database connection lost: {e}")
            logger.info("Attempting to reconnect...")
            try:
                conn.close()
            except Exception:
                pass
            conn = get_connection()

        except Exception as e:
            # Log unexpected errors but don't crash — keep the simulator running
            logger.error(f"Unexpected error in cycle #{cycle}: {e}", exc_info=True)
            conn.rollback()

        time.sleep(CYCLE_SECONDS)


if __name__ == "__main__":
    run_simulation()