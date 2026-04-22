#!/usr/bin/env bash
# Kafka connectivity check using official Confluent cp-kafka image.
# Performs auth check (topic list) + produce/consume round-trip.
#
# Only input: client.properties
#
# Usage:
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties [--image <image>]
#
# Local run (no install needed):
#   docker pull confluentinc/cp-kafka:7.9.0
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Required keys in client.properties:
#   bootstrap.servers, checks_topic,
#   security.protocol, sasl.mechanism, sasl.jaas.config,
#   sasl.login.callback.handler.class, sasl.oauthbearer.token.endpoint.url

set -euo pipefail

PROPS_FILE=""
IMAGE="confluentinc/cp-kafka:6.2.0"

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

# Normalize JAAS config: ensure key=value pairs in sasl.jaas.config have quoted values.
# Key Vault TSV output can strip double-quotes from the rendered template, breaking JAAS parsing.
# Uses awk to selectively quote clientId, clientSecret, scope values on the jaas.config line.
FIXED_PROPS="/tmp/client-fixed-$$.properties"
awk '
/^sasl\.jaas\.config=/ {
    # For each key=value token, quote values that are not already quoted
    n = split($0, parts, " ")
    for (i = 1; i <= n; i++) {
        if (match(parts[i], /^(clientId|clientSecret|scope)=/) && \
            substr(parts[i], RLENGTH+1, 1) != "\"") {
            # Split on first = sign
            eq = index(parts[i], "=")
            k = substr(parts[i], 1, eq)
            v = substr(parts[i], eq+1)
            # Remove trailing ; if present
            hasSemi = (substr(v, length(v)) == ";")
            if (hasSemi) v = substr(v, 1, length(v)-1)
            parts[i] = k "\"" v "\"" (hasSemi ? ";" : "")
        }
    }
    # Rejoin
    line = parts[1]
    for (i = 2; i <= n; i++) line = line " " parts[i]
    print line
    next
}
{ print }
' "$PROPS_FILE" > "$FIXED_PROPS"
PROPS_FILE="$FIXED_PROPS"

# Unique consumer group per run so --from-beginning always works
GROUP="kafka-check-$(date -u +%Y%m%d%H%M%S)-$$"
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"
echo "==> consumer.group=${GROUP}"

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
# Check C — Consume (unique group so --from-beginning always starts fresh)
# -----------------------------------------------------------------------
echo ""
echo "==> [C] Consuming message from '${TOPIC}' group='${GROUP}' (timeout 45s) ..."
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

# Strip log lines (kafka-console-consumer prints "Processed N message(s)" to stderr which
# ends up in CONSUMED when merging; filter to keep only the JSON payload line.
JSON_LINE=$(echo "$CONSUMED" | grep '^{' | head -1 || true)

if [[ -z "$JSON_LINE" ]]; then
  echo "--- consumer output (for debugging) ---"
  echo "$CONSUMED"
  echo "--- end consumer output ---"
  echo "FAIL: No message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed: $JSON_LINE"
echo "PASS: Produce + consume round-trip on '${TOPIC}' successful"
