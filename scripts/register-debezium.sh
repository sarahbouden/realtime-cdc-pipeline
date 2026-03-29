#!/bin/bash
# =============================================================================
# register-debezium.sh
# Registers the Debezium PostgreSQL connector via the Kafka Connect REST API.
#
# Run this ONCE after all containers are healthy:
#   bash scripts/register-debezium.sh
#
# Kafka Connect REST API reference:
#   GET  /connectors              — list all registered connectors
#   POST /connectors              — register a new connector
#   GET  /connectors/{name}/status — check connector health
#   DELETE /connectors/{name}     — remove a connector
# =============================================================================

DEBEZIUM_URL="http://localhost:8083"
CONNECTOR_CONFIG="./debezium/register-connector.json"

echo "Waiting for Debezium REST API to be ready..."
until curl -sf "${DEBEZIUM_URL}/connectors" > /dev/null; do
  echo "  Not ready yet — retrying in 3 seconds..."
  sleep 3
done
echo "Debezium is ready."

echo ""
echo "Registering connector..."
HTTP_STATUS=$(curl -s -o /tmp/debezium-response.json -w "%{http_code}" \
  -X POST "${DEBEZIUM_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d @"${CONNECTOR_CONFIG}")

echo ""
if [ "$HTTP_STATUS" -eq 201 ]; then
  echo "Connector registered successfully (HTTP 201)."
elif [ "$HTTP_STATUS" -eq 409 ]; then
  echo "Connector already exists (HTTP 409) — skipping registration."
else
  echo "Unexpected response (HTTP ${HTTP_STATUS}):"
  cat /tmp/debezium-response.json
  exit 1
fi

echo ""
echo "Checking connector status..."
sleep 3
curl -s "${DEBEZIUM_URL}/connectors/ecommerce-postgres-connector/status" | \
  python3 -m json.tool

echo ""
echo "Topics that should now exist in Kafka:"
echo "  ecommerce.public.orders"
echo "  ecommerce.public.customers"
echo "  ecommerce.public.products"