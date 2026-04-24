#!/usr/bin/env bash
# =============================================================
# Avro Schema produce + consume smoke test
#
# Uses official Confluent Docker images ONLY:
#   - confluentinc/cp-schema-registry:8.2.0 (avro-console-producer/consumer)
#
# Only input: schema-client.properties file (self-contained)
# All Kafka, Schema Registry, and OAuth settings come from that file.
#
# Usage:
#   ./scripts/schema-check.sh --props-file /path/to/schema-client.properties
# =============================================================
set -euo pipefail

PROPS_FILE=""
IMAGE="confluentinc/cp-schema-registry:8.2.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --props-file) PROPS_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$PROPS_FILE" ]; then
  echo "ERROR: --props-file is required"
  exit 1
fi

if [ ! -s "$PROPS_FILE" ]; then
  echo "ERROR: properties file is empty or missing: $PROPS_FILE"
  exit 1
fi

for key in bootstrap.servers schema.registry.url oauth.token.endpoint.url oauth.client.id oauth.client.secret oauth.scope; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: schema-client.properties missing required key: ${key}"
    exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
SR_URL=$(grep '^schema.registry.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
TOPIC=$(grep '^topic=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
TOPIC="${TOPIC:-orders.placed}"

# macOS-compatible absolute path resolution
if command -v realpath &>/dev/null; then
  ABS_PROPS_FILE=$(realpath "$PROPS_FILE")
else
  ABS_PROPS_FILE=$(cd "$(dirname "$PROPS_FILE")" && pwd)/$(basename "$PROPS_FILE")
fi

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> schema.registry.url=${SR_URL}"
echo "==> topic=${TOPIC}"
echo "==> image=${IMAGE}"

# -----------------------------------------------------------
# Step 1 — Avro produce
# -----------------------------------------------------------
SCHEMA_DEF='{"type":"record","name":"OrderPlaced","namespace":"io.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'
TEST_MESSAGE="{\"order_id\":\"schema-check-$(date +%s)\",\"product\":\"test-widget\",\"quantity\":1,\"timestamp\":$(date +%s%3N)}"
CONSUMER_GROUP="schema-check-$(date +%s)"

echo ""
echo "==> [1] Producing Avro message to topic '${TOPIC}' ..."
echo "$TEST_MESSAGE" | docker run --rm -i \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-avro-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --producer.config /tmp/client.properties \
    --property schema.registry.url="$SR_URL" \
    --property value.schema="$SCHEMA_DEF"

echo "PASS: Avro message produced to '${TOPIC}'"

# -----------------------------------------------------------
# Step 2 — Avro consume
# -----------------------------------------------------------
echo ""
echo "==> [2] Consuming Avro message from topic '${TOPIC}' ..."
CONSUMED=$(docker run --rm \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-avro-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --consumer.config /tmp/client.properties \
    --property schema.registry.url="$SR_URL" \
    --group "$CONSUMER_GROUP" \
    --from-beginning \
    --max-messages 1 \
    --consumer-property request.timeout.ms=45000 \
    --timeout-ms 45000 2>&1) || true

JSON_LINE=$(echo "$CONSUMED" | grep -v '^[[:space:]]*$' | grep -v '^\[' | grep '^{' | head -1 || true)
if [[ -z "$JSON_LINE" ]]; then
  JSON_LINE=$(echo "$CONSUMED" | grep '{' | tail -1 || true)
fi

if [[ -z "$JSON_LINE" ]]; then
  echo "--- consumer output ---"
  echo "$CONSUMED"
  echo "--- end output ---"
  echo "FAIL: No Avro message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed : $JSON_LINE"
echo "PASS: Avro produce + consume round-trip successful on '${TOPIC}'"
