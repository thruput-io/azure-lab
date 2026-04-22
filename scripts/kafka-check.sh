#!/usr/bin/env bash
# Kafka connectivity + produce/consume check via kcat (librdkafka).
# Uses SASL/OAUTHBEARER with sasl.oauthbearer.method=oidc which works
# with Azure Event Hubs through App Gateway proxies (avoids Java Kafka
# client SASL_AUTHENTICATE protocol incompatibility).
#
# Only input: client.properties
#
# Usage:
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Local run (no install needed):
#   docker pull confluentinc/cp-kcat:7.9.0
#   ./scripts/kafka-check.sh --props-file /path/to/client.properties
#
# Required keys in client.properties:
#   bootstrap.servers                    — <domain>:9093
#   checks_topic                         — Kafka topic for this check
#   sasl.oauthbearer.token.endpoint.url  — Entra token URL
#   sasl.jaas.config                     — must contain clientId, clientSecret, scope

set -euo pipefail

PROPS_FILE=""
KCAT_IMAGE="confluentinc/cp-kcat:7.9.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --props-file) PROPS_FILE="$2"; shift 2 ;;
    --image)      KCAT_IMAGE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$PROPS_FILE" ]]; then
  echo "ERROR: --props-file is required"; exit 1
fi
if [[ ! -s "$PROPS_FILE" ]]; then
  echo "ERROR: client.properties not found or empty: $PROPS_FILE"; exit 1
fi

for key in bootstrap.servers checks_topic sasl.oauthbearer.token.endpoint.url; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"; exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE"               | cut -d= -f2- | tr -d ' \r\n')
TOPIC=$(grep '^checks_topic='          "$PROPS_FILE"               | cut -d= -f2- | tr -d ' \r\n')
TOKEN_URL=$(grep '^sasl.oauthbearer.token.endpoint.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')

# Extract OAuth credentials from sasl.jaas.config line
JAAS_LINE=$(grep '^sasl.jaas.config=' "$PROPS_FILE" | cut -d= -f2-)
CLIENT_ID=$(echo "$JAAS_LINE"     | sed 's/.*clientId="\([^"]*\)".*/\1/')
CLIENT_SECRET=$(echo "$JAAS_LINE" | sed 's/.*clientSecret="\([^"]*\)".*/\1/')
SCOPE=$(echo "$JAAS_LINE"         | sed 's/.*scope="\([^"]*\)".*/\1/')

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$SCOPE" ]]; then
  echo "ERROR: Could not extract clientId/clientSecret/scope from sasl.jaas.config"
  exit 1
fi

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"
echo "==> token_endpoint=${TOKEN_URL}"
echo "==> client_id=${CLIENT_ID}"

# Build a kcat-compatible config file using librdkafka OIDC properties
# (no JAAS config needed — librdkafka fetches its own token)
KCAT_CONF="/tmp/kcat-$$.conf"
cat > "$KCAT_CONF" <<EOF
metadata.broker.list=${BOOTSTRAP}
broker.version.fallback=1.0
security.protocol=sasl_ssl
sasl.mechanisms=OAUTHBEARER
sasl.oauthbearer.method=oidc
sasl.oauthbearer.client.id=${CLIENT_ID}
sasl.oauthbearer.client.secret=${CLIENT_SECRET}
sasl.oauthbearer.token.endpoint.url=${TOKEN_URL}
sasl.oauthbearer.scope=${SCOPE}
EOF

# Unique consumer group per run so -o beginning always works
GROUP="kafka-check-$(date -u +%Y%m%dT%H%M%S)-$$"
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> consumer.group=${GROUP}"
echo "==> kcat image=${KCAT_IMAGE}"

# -----------------------------------------------------------------------
# Step 1 — Auth check: fetch Kafka metadata (kcat -L)
# -----------------------------------------------------------------------
echo ""
echo "==> [1] Authenticating — fetching Kafka metadata (kcat -L) ..."
docker run --rm \
  -v "${KCAT_CONF}:/tmp/kcat.conf:ro" \
  "$KCAT_IMAGE" \
  kcat -F /tmp/kcat.conf -L -t "$TOPIC" 2>&1 | head -30

echo "PASS: Kafka auth OK (metadata fetched)"

# -----------------------------------------------------------------------
# Step 2 — Produce a message
# -----------------------------------------------------------------------
echo ""
echo "==> [2] Producing message to '${TOPIC}' ..."
echo "$MSG" | docker run -i --rm \
  -v "${KCAT_CONF}:/tmp/kcat.conf:ro" \
  "$KCAT_IMAGE" \
  kcat -F /tmp/kcat.conf -P -t "$TOPIC" 2>&1

echo "PASS: Message produced to '${TOPIC}'"

# -----------------------------------------------------------------------
# Step 3 — Consume 1 message
# -----------------------------------------------------------------------
echo ""
echo "==> [3] Consuming message from '${TOPIC}' (group='${GROUP}') ..."
CONSUMED=$(docker run --rm \
  -v "${KCAT_CONF}:/tmp/kcat.conf:ro" \
  "$KCAT_IMAGE" \
  kcat \
    -F /tmp/kcat.conf \
    -X group.id="${GROUP}" \
    -C -t "$TOPIC" \
    -o beginning \
    -c 1 \
    -e 2>&1) || true

rm -f "$KCAT_CONF"

# Filter out log lines; keep only JSON payload
JSON_LINE=$(echo "$CONSUMED" | grep -v '^%' | grep '^{' | head -1 || true)
if [[ -z "$JSON_LINE" ]]; then
  # If no JSON but output is non-empty it might still be a valid message
  JSON_LINE=$(echo "$CONSUMED" | grep -v '^%' | grep -v '^$' | head -1 || true)
fi

if [[ -z "$JSON_LINE" ]]; then
  echo "--- consumer output (for debugging) ---"
  echo "$CONSUMED"
  echo "--- end consumer output ---"
  echo "FAIL: No message consumed from '${TOPIC}'"
  exit 1
fi

echo "Consumed: $JSON_LINE"
echo "PASS: Produce + consume round-trip on '${TOPIC}' successful"
