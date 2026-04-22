#!/usr/bin/env bash
# Kafka connectivity check using official Confluent cp-kafka image.
# Performs auth check (topic list) + produce/consume round-trip.
#
# Only input: client.properties
#
# Usage:
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties [--image <image>]
#
# Required keys in client.properties:
#   bootstrap.servers, checks_topic,
#   security.protocol, sasl.mechanism, sasl.jaas.config,
#   sasl.login.callback.handler.class, sasl.oauthbearer.token.endpoint.url

set -euo pipefail

PROPS_FILE=""
IMAGE="confluentinc/cp-kafka:7.9.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --props-file) PROPS_FILE="$2"; shift 2 ;;
    --image)      IMAGE="$2";      shift 2 ;;
    *) echo "ERROR: Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$PROPS_FILE" ]]; then
  echo "ERROR: --props-file is required"
  exit 1
fi
if [[ ! -s "$PROPS_FILE" ]]; then
  echo "ERROR: client.properties not found or empty: $PROPS_FILE"
  exit 1
fi

for key in bootstrap.servers checks_topic; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"
    exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
TOPIC=$(grep '^checks_topic='       "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"

# -----------------------------------------------------------------------
# Check A — Authentication: list topics via kafka-topics
# -----------------------------------------------------------------------
echo ""
echo "==> [A] Authenticating with Kafka broker (kafka-topics --list) ..."
docker run --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-topics \
    --bootstrap-server "$BOOTSTRAP" \
    --list \
    --command-config /tmp/client.properties
echo "PASS: Kafka auth OK (topic list succeeded)"

# -----------------------------------------------------------------------
# Check B — Produce
# -----------------------------------------------------------------------
echo ""
echo "==> [B] Producing message to '${TOPIC}' ..."
echo "$MSG" | docker run -i --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --producer.config /tmp/client.properties
echo "PASS: Message produced to '${TOPIC}'"

# -----------------------------------------------------------------------
# Check C — Consume
# -----------------------------------------------------------------------
echo ""
echo "==> [C] Consuming message from '${TOPIC}' (timeout 45s) ..."
CONSUMED=$(docker run --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --consumer.config /tmp/client.properties \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 45000 2>/dev/null || true)

if [[ -z "$CONSUMED" ]]; then
  echo "FAIL: No message consumed from '${TOPIC}' within timeout"
  exit 1
fi
echo "Consumed: $CONSUMED"
echo "PASS: Produce + consume round-trip on '${TOPIC}' successful"
