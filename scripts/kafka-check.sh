#!/usr/bin/env bash
# Kafka connectivity + auth + produce/consume check.
# Uses the official confluentinc/cp-kafka image with SASL/PLAIN + $ConnectionString.
#
# Azure Event Hubs for Kafka officially supports SASL/PLAIN with:
#   username = "$ConnectionString"
#   password = <EventHub namespace primary connection string>
# This is the tested and supported authentication path for Kafka CLI tools.
#
# Only input: client.properties
#
# Usage:
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Local run (no install needed):
#   docker pull confluentinc/cp-kafka:7.9.0
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Required keys in client.properties:
#   bootstrap.servers        — <domain>:9093
#   checks_topic             — Kafka topic for this check
#   sasl.connection.string   — EventHub namespace primary connection string

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

for key in bootstrap.servers checks_topic sasl.connection.string; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"; exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers='      "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
TOPIC=$(grep '^checks_topic='              "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')
CONNECTION_STRING=$(grep '^sasl.connection.string=' "$PROPS_FILE" | cut -d= -f2-)

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"
echo "==> image=${IMAGE}"

# -----------------------------------------------------------------------
# Build a SASL/PLAIN client.properties using the EH connection string.
# Azure EH officially supports: username="$ConnectionString" password=<connection-string>
# -----------------------------------------------------------------------
PLAIN_PROPS="/tmp/kafka-plain-$$.properties"
cat > "$PLAIN_PROPS" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="\$ConnectionString" password="${CONNECTION_STRING}";
EOF

# Unique consumer group per run
GROUP="kafka-check-$(date -u +%Y%m%dT%H%M%S)-$$"
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> consumer.group=${GROUP}"

# -----------------------------------------------------------------------
# Check 1 (SSL) already done by workflow — skipped here
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# Check 2 — Auth: list topics
# -----------------------------------------------------------------------
echo ""
echo "==> [2] Authenticating with Kafka broker (kafka-topics --list) ..."
docker run --rm \
  -v "${PLAIN_PROPS}:/tmp/client.properties:ro" \
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
  -v "${PLAIN_PROPS}:/tmp/client.properties:ro" \
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
  -v "${PLAIN_PROPS}:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-console-consumer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --consumer.config /tmp/client.properties \
    --group "$GROUP" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 45000 2>&1) || true

rm -f "$PLAIN_PROPS"

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
