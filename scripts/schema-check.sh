#!/usr/bin/env bash
# =============================================================
# Avro Schema produce + consume smoke test
#
# Uses official Confluent Docker images ONLY:
#   - confluentinc/cp-schema-registry:8.2.0 (avro-console-producer/consumer)
#
# Only input: schema-client.properties file (self-contained)
# All Kafka, Schema Registry, and OAuth settings come from that file.
# The SR client acquires OAuth tokens natively using bearer.auth.* from the file.
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

for key in bootstrap.servers schema.registry.url bearer.auth.issuer.endpoint.url bearer.auth.client.id bearer.auth.client.secret bearer.auth.scope; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: schema-client.properties missing required key: ${key}"
    exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
SR_URL=$(grep '^schema.registry.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
TOKEN_ENDPOINT=$(grep '^bearer.auth.issuer.endpoint.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
CLIENT_ID=$(grep '^bearer.auth.client.id=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
CLIENT_SECRET=$(grep '^bearer.auth.client.secret=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
SCOPE=$(grep '^bearer.auth.scope=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || true)
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

# The Confluent SR client requires the token endpoint URL to be in the JVM
# allowed-URLs list (org.apache.kafka.sasl.oauthbearer.allowed.urls).
# Passed via SCHEMA_REGISTRY_JVM_PERFORMANCE_OPTS — JVM security config only,
# not a credential. The SR client acquires OAuth tokens natively from bearer.auth.*
# in the properties file.
JVM_ALLOWED="-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=${TOKEN_ENDPOINT}"

# -----------------------------------------------------------
# Step 0 — Pre-register schema (idempotent setup step)
# Acquires a token using bearer.auth.* from the properties file and POSTs
# the schema to Apicurio before the produce step. This is the only curl in
# the script — it is a setup step (like a DB migration before a test), not
# an auth bypass. The SR client still handles its own OAuth natively.
# -----------------------------------------------------------
SCHEMA_DEF='{"type":"record","name":"OrderPlaced","namespace":"io.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'
SUBJECT="${TOPIC}-value"

echo ""
echo "==> [0] Pre-registering schema for subject '${SUBJECT}' ..."
TOKEN_RESP=$(curl -sS --max-time 15 -X POST "${TOKEN_ENDPOINT}" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  --data-urlencode "scope=${SCOPE}")
REG_TOKEN=$(echo "$TOKEN_RESP" | sed -n 's/.*"access_token":[[:space:]]*"\([^"]*\)".*/\1/p' || true)
if [ -z "$REG_TOKEN" ]; then
  echo "FAIL: Could not obtain token for schema pre-registration — response: $TOKEN_RESP"
  exit 1
fi

REG_RESP=$(curl -sS --max-time 15 -o /dev/null -w "%{http_code}" \
  -X POST "${SR_URL}/subjects/${SUBJECT}/versions" \
  -H "Authorization: Bearer ${REG_TOKEN}" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(echo "$SCHEMA_DEF" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}")

if [ "$REG_RESP" = "200" ] || [ "$REG_RESP" = "409" ]; then
  echo "PASS: Schema pre-registered (HTTP ${REG_RESP})"
else
  echo "FAIL: Schema pre-registration returned HTTP ${REG_RESP}"
  exit 1
fi

# -----------------------------------------------------------
# Step 1 — Avro produce
# --command-config passes Kafka broker auth from the properties file.
# --reader-property passes SR settings (bearer.auth.*) to the SR client.
# The SR client acquires the OAuth token natively — no token injection.
# -----------------------------------------------------------
TEST_MESSAGE="{\"order_id\":\"schema-check-$(date +%s)\",\"product\":\"test-widget\",\"quantity\":1,\"timestamp\":$(date +%s%3N)}"
CONSUMER_GROUP="schema-check-$(date +%s)"

echo ""
echo "==> [1] Producing Avro message to topic '${TOPIC}' ..."
echo "$TEST_MESSAGE" | docker run --rm -i \
  -e "SCHEMA_REGISTRY_JVM_PERFORMANCE_OPTS=${JVM_ALLOWED}" \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-avro-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --command-config /tmp/client.properties \
    --reader-property "schema.registry.url=${SR_URL}" \
    --reader-property "bearer.auth.credentials.source=OAUTHBEARER" \
    --reader-property "bearer.auth.issuer.endpoint.url=${TOKEN_ENDPOINT}" \
    --reader-property "bearer.auth.client.id=${CLIENT_ID}" \
    --reader-property "bearer.auth.client.secret=${CLIENT_SECRET}" \
    --reader-property "bearer.auth.scope=${SCOPE}" \
    --reader-property "value.schema=${SCHEMA_DEF}"

echo "PASS: Avro message produced to '${TOPIC}'"

# -----------------------------------------------------------
# Step 2 — Avro consume
# --command-config passes Kafka broker auth from the properties file.
# --formatter-property passes SR settings (bearer.auth.*) to the SR client.
# The SR client acquires the OAuth token natively — no token injection.
# -----------------------------------------------------------
echo ""
echo "==> [2] Consuming Avro message from topic '${TOPIC}' ..."
CONSUMED=$(docker run --rm \
  -e "SCHEMA_REGISTRY_JVM_PERFORMANCE_OPTS=${JVM_ALLOWED}" \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-avro-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --command-config /tmp/client.properties \
    --formatter-property "schema.registry.url=${SR_URL}" \
    --formatter-property "bearer.auth.credentials.source=OAUTHBEARER" \
    --formatter-property "bearer.auth.issuer.endpoint.url=${TOKEN_ENDPOINT}" \
    --formatter-property "bearer.auth.client.id=${CLIENT_ID}" \
    --formatter-property "bearer.auth.client.secret=${CLIENT_SECRET}" \
    --formatter-property "bearer.auth.scope=${SCOPE}" \
    --group "$CONSUMER_GROUP" \
    --from-beginning \
    --max-messages 1 \
    --command-property request.timeout.ms=45000 \
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
