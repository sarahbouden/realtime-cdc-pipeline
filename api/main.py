"""
main.py — Lightweight REST API exposing DuckDB metrics for Grafana
==================================================================
Grafana's built-in "JSON API" datasource (simpod-json-datasource) can
query any REST API that follows a simple protocol. This service implements
that protocol, reading directly from DuckDB.

Endpoints:
  GET  /           → health check
  POST /search     → list available metrics
  POST /query      → return time series or table data
"""

import os
import json
import duckdb
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

DUCKDB_PATH = os.getenv("DUCKDB_PATH", "/warehouse/ecommerce.duckdb")
PORT = int(os.getenv("API_PORT", 3001))


def query_duckdb(sql: str) -> list:
    try:
        con = duckdb.connect(DUCKDB_PATH, read_only=True)
        result = con.execute(sql).fetchall()
        con.close()
        return result
    except Exception as e:
        print(f"DuckDB error: {e}")
        return []


class GrafanaHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # suppress default request logging

    def send_json(self, data, status=200):
        body = json.dumps(data, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/":
            self.send_json({"status": "ok", "duckdb": DUCKDB_PATH})
        elif self.path == "/metrics":
            self.handle_metrics()
        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}

        if self.path == "/search":
            self.send_json([
                "orders_by_status",
                "hourly_revenue",
                "hourly_order_volume",
                "cancellation_rate"
            ])

        elif self.path == "/query":
            results = []
            for target in body.get("targets", []):
                name = target.get("target", "")
                results.append(self.build_response(name))
            self.send_json(results)

        else:
            self.send_json({"error": "not found"}, 404)

    def handle_metrics(self):
        rows = query_duckdb("""
            SELECT status, COUNT(*) as cnt
            FROM fct_orders
            GROUP BY status ORDER BY cnt DESC
        """)
        self.send_json([{"status": r[0], "count": r[1]} for r in rows])

    def build_response(self, target: str) -> dict:
        if target == "orders_by_status":
            rows = query_duckdb("""
                SELECT status, COUNT(*) as cnt
                FROM fct_orders GROUP BY status ORDER BY cnt DESC
            """)
            return {
                "type": "table",
                "columns": [
                    {"text": "Status", "type": "string"},
                    {"text": "Orders", "type": "number"}
                ],
                "rows": [[r[0], r[1]] for r in rows]
            }

        elif target == "hourly_revenue":
            rows = query_duckdb("""
                SELECT
                    epoch_ms(metric_hour::TIMESTAMP) AS ts,
                    gross_revenue
                FROM fct_order_metrics
                ORDER BY metric_hour DESC LIMIT 48
            """)
            return {
                "target": "Gross Revenue",
                "datapoints": [[float(r[1] or 0), r[0]] for r in rows]
            }

        elif target == "hourly_order_volume":
            rows = query_duckdb("""
                SELECT
                    epoch_ms(metric_hour::TIMESTAMP) AS ts,
                    total_orders
                FROM fct_order_metrics
                ORDER BY metric_hour DESC LIMIT 48
            """)
            return {
                "target": "Total Orders",
                "datapoints": [[int(r[1] or 0), r[0]] for r in rows]
            }

        elif target == "cancellation_rate":
            rows = query_duckdb("""
                SELECT
                    epoch_ms(metric_hour::TIMESTAMP) AS ts,
                    cancellation_rate_pct
                FROM fct_order_metrics
                ORDER BY metric_hour DESC LIMIT 48
            """)
            return {
                "target": "Cancellation Rate %",
                "datapoints": [[float(r[1] or 0), r[0]] for r in rows]
            }

        return {"target": target, "datapoints": []}


if __name__ == "__main__":
    print(f"Starting Grafana JSON API on port {PORT}")
    print(f"DuckDB path: {DUCKDB_PATH}")
    server = HTTPServer(("0.0.0.0", PORT), GrafanaHandler)
    server.serve_forever()