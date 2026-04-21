#!/usr/bin/env bash

set -euo pipefail

PROPS_FILE=""
TOPIC="orders.placed"
IMAGE="confluentinc/cp-schema-registry:7.6.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --props-file)
    PROPS_FILE="$2"
    shift 2
    ;;
  --topic)
    TOPIC="$2"
    shift 2
    ;;
  --image)
    IMAGE="$2"
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

if ! grep -q '^bootstrap.servers=' "$PROPS_FILE"; then
  echo "ERROR: client.properties missing bootstrap.servers"
  exit 1
fi

if ! grep -q '^schema.registry.url=' "$PROPS_FILE"; then
  echo "ERROR: client.properties missing schema.registry.url"
  exit 1
fi

if ! grep -q '^schema.registry.basic.auth.user.info=' "$PROPS_FILE"; then
  echo "ERROR: client.properties missing schema.registry.basic.auth.user.info"
  exit 1
fi

echo "==> Pulling Confluent image $IMAGE ..."
docker pull "$IMAGE"

EXPECTED_TS=$(( $(date +%s) * 1000 ))
VALUE_SCHEMA='{"type":"record","name":"OrderPlaced","namespace":"se.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'
echo "==> Producing one Avro message to topic $TOPIC (timestamp=$EXPECTED_TS) ..."
docker run --rm \
  -v "$PROPS_FILE:/etc/kafka/client.properties:ro" \
  -e TOPIC="$TOPIC" \
  -e EXPECTED_TS="$EXPECTED_TS" \
  -e VALUE_SCHEMA="$VALUE_SCHEMA" \
  "$IMAGE" \
  bash -c '
    echo "{\"order_id\":\"check-$EXPECTED_TS\",\"product\":\"endpoint-check\",\"quantity\":1,\"timestamp\":$EXPECTED_TS}" | \
    kafka-avro-console-producer \
      --broker-list "$(grep "^bootstrap.servers" /etc/kafka/client.properties | cut -d= -f2-)" \
      --topic "$TOPIC" \
      --property schema.registry.url="$(grep "^schema.registry.url" /etc/kafka/client.properties | cut -d= -f2-)" \
      --property basic.auth.credentials.source=USER_INFO \
      --property schema.registry.basic.auth.user.info="$(grep "^schema.registry.basic.auth.user.info" /etc/kafka/client.properties | cut -d= -f2-)" \
      --property value.schema="$VALUE_SCHEMA" \
      --property auto.register.schemas=false \
      --property use.latest.version=true \
      --producer.config /etc/kafka/client.properties
  '

echo "==> Consuming the Avro message from topic $TOPIC (expecting timestamp=$EXPECTED_TS) ..."
CONSUMED=$(docker run --rm \
  -v "$PROPS_FILE:/etc/kafka/client.properties:ro" \
  -e TOPIC="$TOPIC" \
  "$IMAGE" \
  bash -c '
    kafka-avro-console-consumer \
      --bootstrap-server "$(grep "^bootstrap.servers" /etc/kafka/client.properties | cut -d= -f2-)" \
      --topic "$TOPIC" \
      --max-messages 1 \
      --timeout-ms 30000 \
      --property schema.registry.url="$(grep "^schema.registry.url" /etc/kafka/client.properties | cut -d= -f2-)" \
      --property basic.auth.credentials.source=USER_INFO \
      --property schema.registry.basic.auth.user.info="$(grep "^schema.registry.basic.auth.user.info" /etc/kafka/client.properties | cut -d= -f2-)" \
      --consumer.config /etc/kafka/client.properties
  ' 2>/dev/null)

echo "Consumed: $CONSUMED"
if echo "$CONSUMED" | grep -q "\"timestamp\":$EXPECTED_TS"; then
  echo "PASS: Consumed message matches expected timestamp $EXPECTED_TS"
else
  echo "FAIL: Consumed message does not contain expected timestamp $EXPECTED_TS"
  exit 1
fi

echo "PASS: Produce + Consume completed successfully"
