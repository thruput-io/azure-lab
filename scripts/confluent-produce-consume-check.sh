#!/usr/bin/env bash
# Confluent-standard Kafka Avro produce + consume smoke test.
# Uses confluentinc/cp-schema-registry image (kafka-avro-console-producer/consumer).
# Schema Registry auth: Confluent OAUTHBEARER Bearer token from Entra ID.
# Kafka broker auth: SASL/OAUTHBEARER via App Gateway (port 9093).
#
# Usage:
#   ./confluent-produce-consume-check.sh --props-file /path/to/client.properties [--image <image>] [--topic <topic>]
#
# Required keys in client.properties:
#   bootstrap.servers, schema.registry.url,
#   bearer.auth.issuer.endpoint.url, bearer.auth.client.id, bearer.auth.client.secret,
#   bearer.auth.scope (optional, defaults to https://eventhubs.azure.net/.default),
#   security.protocol, sasl.mechanism, sasl.jaas.config,
#   sasl.login.callback.handler.class, sasl.oauthbearer.token.endpoint.url

set -euo pipefail

PROPS_FILE=""
IMAGE="confluentinc/cp-schema-registry:7.6.0"
TOPIC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --props-file)
    PROPS_FILE="$2"
    shift 2
    ;;
  --image)
    IMAGE="$2"
    shift 2
    ;;
  --topic)
    TOPIC="$2"
    shift 2
    ;;
  *)
    echo "ERROR: Unknown argument: $1"
    exit 1
    ;;
  esac
done

if [[ -z "$PROPS_FILE" ]]; then
  echo "ERROR: --props-file is required"
  exit 1
fi

if [[ ! -f "$PROPS_FILE" ]]; then
  echo "ERROR: client.properties file not found: $PROPS_FILE"
  exit 1
fi

if [[ ! -s "$PROPS_FILE" ]]; then
  echo "ERROR: client.properties file is empty: $PROPS_FILE"
  exit 1
fi

for key in bootstrap.servers schema.registry.url bearer.auth.issuer.endpoint.url bearer.auth.client.id bearer.auth.client.secret; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"
    exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
SR_URL=$(grep '^schema.registry.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
ISSUER_URL=$(grep '^bearer.auth.issuer.endpoint.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
CLIENT_ID=$(grep '^bearer.auth.client.id=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
CLIENT_SECRET=$(grep '^bearer.auth.client.secret=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
SCOPE=$(grep '^bearer.auth.scope=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || echo "https://eventhubs.azure.net/.default")

if [[ -z "$TOPIC" ]]; then
  TOPIC=$(grep '^topic=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n' || echo "orders.placed")
fi

if [[ -z "$SCOPE" ]]; then
  SCOPE="https://eventhubs.azure.net/.default"
fi

EXPECTED_TS=$(date +%s%3N)
ORDER_ID="check-${EXPECTED_TS}"

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> schema.registry.url=${SR_URL}"
echo "==> topic=${TOPIC}"
echo "==> order_id=${ORDER_ID}"

# Avro schema for the topic (TopicNameStrategy subject: orders.placed-value)
AVRO_SCHEMA='{"type":"record","name":"OrderPlaced","namespace":"se.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'

echo "==> Getting OAuth token for Schema Registry..."
TOKEN_RESP=$(curl -sS -X POST "$ISSUER_URL" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=${SCOPE}")
ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "ERROR: Failed to acquire OAuth token from $ISSUER_URL"
  echo "$TOKEN_RESP"
  exit 1
fi
echo "Token acquired (length=${#ACCESS_TOKEN})"

echo "==> Registering Avro schema (TopicNameStrategy subject: ${TOPIC}-value)..."
SUBJECT="${TOPIC}-value"
REG_STATUS=$(curl -sS -o /tmp/sr_reg_resp.json -w "%{http_code}" \
  -X POST "${SR_URL}/subjects/${SUBJECT}/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d "{\"schema\": $(echo "$AVRO_SCHEMA" | jq -Rs .)}")

echo "Schema registration HTTP status: $REG_STATUS"
cat /tmp/sr_reg_resp.json
echo ""
if [[ "$REG_STATUS" != "200" && "$REG_STATUS" != "409" ]]; then
  echo "ERROR: Schema registration failed (HTTP $REG_STATUS)"
  exit 1
fi

# Write producer config (schema registry uses Bearer auth via --producer.config)
PRODUCER_CFG=$(mktemp)
cat > "$PRODUCER_CFG" <<EOF
bootstrap.servers=${BOOTSTRAP}
security.protocol=$(grep '^security.protocol=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
sasl.mechanism=$(grep '^sasl.mechanism=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
sasl.login.callback.handler.class=$(grep '^sasl.login.callback.handler.class=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
sasl.oauthbearer.token.endpoint.url=$(grep '^sasl.oauthbearer.token.endpoint.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
sasl.jaas.config=$(grep '^sasl.jaas.config=' "$PROPS_FILE" | cut -d= -f2-)
schema.registry.url=${SR_URL}
basic.auth.credentials.source=OAUTHBEARER
bearer.auth.credentials.source=OAUTHBEARER
bearer.auth.issuer.endpoint.url=${ISSUER_URL}
bearer.auth.client.id=${CLIENT_ID}
bearer.auth.client.secret=${CLIENT_SECRET}
bearer.auth.scope=${SCOPE}
EOF

cp "$PRODUCER_CFG" /tmp/producer.properties
cp "$PRODUCER_CFG" /tmp/consumer.properties
echo "group.id=smoke-test-${EXPECTED_TS}" >> /tmp/consumer.properties
echo "auto.offset.reset=latest" >> /tmp/consumer.properties

echo "==> Producing Avro message via Confluent container..."
docker run --rm \
  -v /tmp/producer.properties:/etc/kafka/producer.properties:ro \
  "$IMAGE" \
  bash -c "echo '{\"order_id\":\"${ORDER_ID}\",\"product\":\"endpoint-check\",\"quantity\":1,\"timestamp\":${EXPECTED_TS}}' | \
    kafka-avro-console-producer \
      --broker-list '${BOOTSTRAP}' \
      --topic '${TOPIC}' \
      --producer.config /etc/kafka/producer.properties \
      --property schema.registry.url='${SR_URL}' \
      --property value.schema='${AVRO_SCHEMA}' \
      --property value.subject.name.strategy=io.confluent.kafka.serializers.subject.TopicNameStrategy"

echo "==> Consuming Avro message via Confluent container..."
CONSUME_OUT=$(docker run --rm \
  -v /tmp/consumer.properties:/etc/kafka/consumer.properties:ro \
  "$IMAGE" \
  bash -c "kafka-avro-console-consumer \
    --bootstrap-server '${BOOTSTRAP}' \
    --topic '${TOPIC}' \
    --consumer.config /etc/kafka/consumer.properties \
    --property schema.registry.url='${SR_URL}' \
    --property value.subject.name.strategy=io.confluent.kafka.serializers.subject.TopicNameStrategy \
    --max-messages 1 \
    --timeout-ms 30000 2>/dev/null" || true)

echo "Consumed: $CONSUME_OUT"

if echo "$CONSUME_OUT" | grep -q "\"timestamp\":${EXPECTED_TS}"; then
  echo "PASS: Smoke test completed — message round-trip verified (timestamp=${EXPECTED_TS})"
else
  echo "ERROR: Did not find expected message with timestamp=${EXPECTED_TS} in consumed output"
  echo "Consumed output: $CONSUME_OUT"
  exit 1
fi

rm -f "$PRODUCER_CFG" /tmp/producer.properties /tmp/consumer.properties
