#!/usr/bin/env bash
# Kafka connectivity + auth + produce/consume check.
# Uses the official confluentinc/cp-kafka image.
#
# client.properties is the single source of truth — all Kafka settings
# (bootstrap.servers, security.protocol, sasl.mechanism, sasl.jaas.config,
# checks_topic) come from that file and are passed directly to cp-kafka
# with no additional parameter construction.
#
# Usage:
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Local run (no install needed):
#   docker pull confluentinc/cp-kafka:7.9.0
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Required keys in client.properties:
#   bootstrap.servers   — <domain>:9093
#   checks_topic        — Kafka topic for this check
#   security.protocol   — e.g. SASL_SSL
#   sasl.mechanism      — e.g. PLAIN
#   sasl.jaas.config    — full JAAS entry for the chosen mechanism

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
  echo "ERROR: --props-file is required"; exit 1
fi
if [[ ! -s "$PROPS_FILE" ]]; then
  echo "ERROR: client.properties not found or empty: $PROPS_FILE"; exit 1
fi

for key in bootstrap.servers checks_topic security.protocol sasl.mechanism sasl.jaas.config; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"; exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
TOPIC=$(grep     '^checks_topic='      "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"
echo "==> image=${IMAGE}"

# Unique consumer group per run
GROUP="kafka-check-$(date -u +%Y%m%dT%H%M%S)-$$"
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> consumer.group=${GROUP}"

# -----------------------------------------------------------------------
# Check 2 — Auth: list topics
# client.properties is passed directly — no extra construction needed.
# -----------------------------------------------------------------------
echo ""
echo "==> [2] Authenticating with Kafka broker (kafka-topics --list) ..."
docker run --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-topics \
    --bootstrap-server "$BOOTSTRAP" \
    --list \
    --command-config /tmp/client.properties
echo "PASS: Kafka auth OK (topic list succeeded)"

# -----------------------------------------------------------------------
# Check 3 — Produce a message
# -----------------------------------------------------------------------
echo ""
echo "==> [3] Producing message to '${TOPIC}' ..."
echo "$MSG" | docker run -i --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --producer.config /tmp/client.properties
echo "PASS: Message produced to '${TOPIC}'"

# -----------------------------------------------------------------------
# Check 4 — Consume 1 message
# -----------------------------------------------------------------------
echo ""
echo "==> [4] Consuming message from '${TOPIC}' (group='${GROUP}', timeout 45s) ..."
CONSUMED=$(docker run --rm \
  -v "${PROPS_FILE}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --consumer.config /tmp/client.properties \
    --group "$GROUP" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 45000 2>&1) || true

# Filter out Java log lines; keep the JSON payload
JSON_LINE=$(echo "$CONSUMED" | grep -v '^[[:space:]]*$' | grep -v '^\[' | grep '^{' | head -1 || true)
if [[ -z "$JSON_LINE" ]]; then
  JSON_LINE=$(echo "$CONSUMED" | grep '{' | tail -1 || true)
fi

if [[ -z "$JSON_LINE" ]]; then
  echo "--- consumer output ---"
  echo "$CONSUMED"
  echo "--- end output ---"
  echo "FAIL: No message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed: $JSON_LINE"
echo "PASS: Produce + consume round-trip on '${TOPIC}' successful"
