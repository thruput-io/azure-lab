#!/usr/bin/env bash
# =============================================================
# Avro Schema produce + consume smoke test
#
# Uses official Confluent Docker images ONLY:
#   - confluentinc/cp-schema-registry:8.2.0 (avro-console-producer/consumer)
#
# Only input: schema-client.properties file (self-contained)
#
# Usage:
#   ./scripts/schema-check.sh --props-file /path/to/schema-client.properties
# =============================================================
set -euo pipefail

CONFLUENT_IMAGE="confluentinc/cp-schema-registry:8.2.0"
SCHEMA_NAME="OrderPlaced"
SCHEMA_DEF='{"type":"record","name":"OrderPlaced","namespace":"io.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'

# -----------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------
PROPS_FILE=""
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

# -----------------------------------------------------------
# Parse properties for local use (curl)
# -----------------------------------------------------------
get_prop() {
  grep "^${1}=" "$PROPS_FILE" | head -1 | cut -d= -f2-
}

BOOTSTRAP=$(get_prop "bootstrap.servers")
SR_URL=$(get_prop "schema.registry.url")

# Try new oauth keys first, then fallback to SASL keys for baseline
TOKEN_ENDPOINT=$(get_prop "oauth.token.endpoint.url")
if [ -z "$TOKEN_ENDPOINT" ]; then
  TOKEN_ENDPOINT=$(get_prop "sasl.oauthbearer.token.endpoint.url")
fi

CLIENT_ID=$(get_prop "oauth.client.id")
CLIENT_SECRET=$(get_prop "oauth.client.secret")
SCOPE=$(get_prop "oauth.scope")

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  JAAS=$(get_prop "sasl.jaas.config")
  if [ -n "$JAAS" ]; then
    CLIENT_ID=$(echo "$JAAS"     | sed -n 's/.*clientId="\([^"]*\)".*/\1/p')
    CLIENT_SECRET=$(echo "$JAAS" | sed -n 's/.*clientSecret="\([^"]*\)".*/\1/p')
    if [ -z "$SCOPE" ]; then
      SCOPE=$(echo "$JAAS"       | sed -n 's/.*scope="\([^"]*\)".*/\1/p')
    fi
  fi
fi

if [ -z "$SCOPE" ]; then
  SCOPE="https://eventhubs.azure.net/.default"
fi

for var in BOOTSTRAP SR_URL TOKEN_ENDPOINT CLIENT_ID CLIENT_SECRET SCOPE; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Could not parse $var from $PROPS_FILE"
    exit 1
  fi
done

TOPIC=$(get_prop "topic")
if [ -z "$TOPIC" ]; then
  TOPIC="orders.placed"
fi

echo "bootstrap  : $BOOTSTRAP"
echo "sr_url     : $SR_URL"
echo "topic      : $TOPIC"
echo "scope      : $SCOPE"

# -----------------------------------------------------------
# Step 1 — Acquire OAuth Bearer token
# -----------------------------------------------------------
echo ""
echo "==> [1] Acquiring OAuth Bearer token ..."
TOKEN_RESP=$(curl -sS --max-time 15 -X POST "$TOKEN_ENDPOINT" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  -d "scope=${SCOPE}")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | sed -n 's/.*"access_token":[[:space:]]*"\([^"]*\)".*/\1/p' || true)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "FAIL: Could not obtain OAuth token — response: $TOKEN_RESP"
  exit 1
fi
echo "PASS: OAuth token acquired"

# -----------------------------------------------------------
# Step 2 — Register Avro schema
# -----------------------------------------------------------
echo ""
echo "==> [2] Registering Avro schema '${SCHEMA_NAME}' ..."

ESCAPED_SCHEMA_DEF=$(echo "$SCHEMA_DEF" | sed 's/"/\\"/g')
CONFLUENT_SCHEMA_PAYLOAD="{\"schema\":\"$ESCAPED_SCHEMA_DEF\"}"

# Use absolute URL to handle potential App Gateway path issues
# Apicurio uses /subjects/...
# Azure EH SR also uses /subjects/... in its Confluent-compatible mode
REGISTER_RESP=$(curl -sS --max-time 15 \
  -X POST "${SR_URL}/subjects/${SCHEMA_NAME}/versions" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data-raw "$CONFLUENT_SCHEMA_PAYLOAD")

SCHEMA_ID=$(echo "$REGISTER_RESP" | sed -n 's/.*"id":[[:space:]]*\([0-9]*\).*/\1/p' || true)
if [ -z "$SCHEMA_ID" ]; then
  echo "FAIL: Schema registration failed — response: $REGISTER_RESP"
  exit 1
fi
echo "PASS: Schema registered — id=${SCHEMA_ID}"

# -----------------------------------------------------------
# Step 3 — Avro produce + consume
# -----------------------------------------------------------
TEST_MESSAGE="{\"order_id\":\"schema-check-$(date +%s)\",\"product\":\"test-widget\",\"quantity\":1,\"timestamp\":$(date +%s%3N)}"
CONSUMER_GROUP="schema-check-$(date +%s)"

# Use absolute path for mounting
ABS_PROPS_FILE=$(readlink -f "$PROPS_FILE")

echo ""
echo "==> [3a] Producing Avro message to topic '${TOPIC}' ..."
echo "$TEST_MESSAGE" | docker run --rm -i \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$CONFLUENT_IMAGE" \
  kafka-avro-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --producer.config /tmp/client.properties \
    --property schema.registry.url="$SR_URL" \
    --property value.schema="$SCHEMA_DEF" \
    --property bearer.auth.credentials.source=OAUTHBEARER \
    --property "bearer.auth.token=${ACCESS_TOKEN}"

echo "PASS: Avro message produced to '${TOPIC}'"

echo ""
echo "==> [3b] Consuming Avro message from topic '${TOPIC}' ..."
CONSUMED=$(docker run --rm \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$CONFLUENT_IMAGE" \
  kafka-avro-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --consumer.config /tmp/client.properties \
    --property schema.registry.url="$SR_URL" \
    --property bearer.auth.credentials.source=OAUTHBEARER \
    --property "bearer.auth.token=${ACCESS_TOKEN}" \
    --group "$CONSUMER_GROUP" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 45000 \
  | grep -v "^Processed\|^$" | tail -1)

if [ -z "$CONSUMED" ]; then
  echo "FAIL: No Avro message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed : $CONSUMED"
echo "PASS: Avro produce + consume round-trip successful on '${TOPIC}'"
