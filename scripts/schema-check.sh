#!/usr/bin/env bash
# =============================================================
# Avro Schema produce + consume smoke test
#
# Uses official Confluent Docker images ONLY:
#   - confluentinc/cp-schema-registry:7.9.0  (schema registration,
#                                             avro-console-producer/consumer)
#
# Only input: client.properties file
#
# Usage:
#   ./scripts/schema-check.sh --props-file /path/to/client.properties
#
# Required keys in client.properties:
#   bootstrap.servers
#   topic
#   sasl.oauthbearer.token.endpoint.url
#   sasl.jaas.config   (contains clientId, clientSecret)
# =============================================================
set -euo pipefail

CONFLUENT_IMAGE="confluentinc/cp-schema-registry:7.9.0"
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
  echo "ERROR: client.properties file is empty or missing: $PROPS_FILE"
  exit 1
fi

# -----------------------------------------------------------
# Parse client.properties
# -----------------------------------------------------------
get_prop() {
  grep "^${1}=" "$PROPS_FILE" | head -1 | cut -d= -f2-
}

BOOTSTRAP=$(get_prop "bootstrap.servers")
TOPIC=$(get_prop "topic")
TOKEN_ENDPOINT=$(get_prop "sasl.oauthbearer.token.endpoint.url")
JAAS=$(get_prop "sasl.jaas.config")
SR_URL=$(get_prop "schema.registry.url")
CONNECTION_STRING=$(get_prop "sasl.connection.string")

CLIENT_ID=$(echo "$JAAS"     | sed -n 's/.*clientId="\([^"]*\)".*/\1/p')
CLIENT_SECRET=$(echo "$JAAS" | sed -n 's/.*clientSecret="\([^"]*\)".*/\1/p')
DOMAIN=$(echo "$BOOTSTRAP"   | cut -d: -f1)

for var in BOOTSTRAP TOPIC TOKEN_ENDPOINT CLIENT_ID CLIENT_SECRET SR_URL CONNECTION_STRING; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Could not parse $var from client.properties"
    exit 1
  fi
done

echo "bootstrap  : $BOOTSTRAP"
echo "topic      : $TOPIC"
echo "sr_url     : $SR_URL"

# -----------------------------------------------------------
# Step 1 — Acquire Entra ID Bearer token
# -----------------------------------------------------------
echo ""
echo "==> [1] Acquiring Entra ID Bearer token ..."
TOKEN_RESP=$(curl -sS --max-time 15 -X POST "$TOKEN_ENDPOINT" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  -d "scope=https://eventhubs.azure.net/.default")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | sed -n 's/.*"access_token":[[:space:]]*"\([^"]*\)".*/\1/p' || true)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "FAIL: Could not obtain OAuth token — response: $TOKEN_RESP"
  exit 1
fi
echo "PASS: OAuth token acquired"

# -----------------------------------------------------------
# Step 2 — Register Avro schema via Confluent-compatible SR REST API
# -----------------------------------------------------------
echo ""
echo "==> [2] Registering Avro schema '${SCHEMA_NAME}' via Confluent API ..."

# Wrap schema in the expected Confluent JSON format: {"schema": "..."}
ESCAPED_SCHEMA_DEF=$(echo "$SCHEMA_DEF" | sed 's/"/\\"/g')
CONFLUENT_SCHEMA_PAYLOAD="{\"schema\":\"$ESCAPED_SCHEMA_DEF\"}"

REGISTER_RESP=$(curl -sS --max-time 15 \
  -X POST "${SR_URL}/subjects/${SCHEMA_NAME}/versions" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data-raw "$CONFLUENT_SCHEMA_PAYLOAD")

# Confluent registration returns the numeric ID: {"id": 1}
SCHEMA_ID=$(echo "$REGISTER_RESP" | sed -n 's/.*"id":[[:space:]]*\([0-9]*\).*/\1/p' || true)
if [ -z "$SCHEMA_ID" ]; then
  echo "FAIL: Schema registration failed — response: $REGISTER_RESP"
  echo "TIP: If response is 404, check if App Gateway needs a Rewrite Rule for /$schemaregistry"
  exit 1
fi
echo "PASS: Schema registered — id=${SCHEMA_ID}"

# -----------------------------------------------------------
# Step 3 — Avro produce + consume via confluentinc/cp-schema-registry
# -----------------------------------------------------------
# Build Kafka auth using SASL/PLAIN + $ConnectionString — same proven pattern as kafka-check.sh.
# SR auth uses a separate OAuth bearer token (acquired in Step 1).
CONFLUENT_PROPS_FILE=$(mktemp /tmp/confluent-props.XXXXXX)
cat > "$CONFLUENT_PROPS_FILE" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="\$ConnectionString" password="${CONNECTION_STRING}";
schema.registry.url=${SR_URL}
EOF

TEST_MESSAGE="{\"order_id\":\"schema-check-$(date +%s)\",\"product\":\"test-widget\",\"quantity\":1,\"timestamp\":$(date +%s%3N)}"
CONSUMER_GROUP="schema-check-$(date +%s)"

echo ""
echo "==> [3a] Producing Avro message to topic '${TOPIC}' ..."
echo "$TEST_MESSAGE" | docker run --rm -i \
  -v "$CONFLUENT_PROPS_FILE:/tmp/client.properties:ro" \
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
  -v "$CONFLUENT_PROPS_FILE:/tmp/client.properties:ro" \
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

rm -f "$CONFLUENT_PROPS_FILE"

if [ -z "$CONSUMED" ]; then
  echo "FAIL: No Avro message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed : $CONSUMED"
echo "PASS: Avro produce + consume round-trip successful on '${TOPIC}'"
