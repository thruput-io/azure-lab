#!/usr/bin/env bash
# Kafka connectivity + auth + produce/consume check.
# Uses the official confluentinc/cp-kafka image with SASL/PLAIN.
#
# Azure Event Hubs supports two SASL auth modes:
#   1. SASL/PLAIN with connection string ($ConnectionString:password)
#   2. SASL/PLAIN with OAuth token ($OAuth:JWT)
# This script uses mode 2: acquires an Entra ID JWT then authenticates
# with sasl.mechanism=PLAIN, username=$OAuth, password=<JWT>
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
#   bootstrap.servers                    — <domain>:9093
#   checks_topic                         — Kafka topic for this check
#   sasl.oauthbearer.token.endpoint.url  — Entra token URL
#   sasl.jaas.config                     — must contain clientId, clientSecret, scope

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

for key in bootstrap.servers checks_topic sasl.oauthbearer.token.endpoint.url; do
  if ! grep -q "^${key}=" "$PROPS_FILE"; then
    echo "ERROR: client.properties missing required key: ${key}"; exit 1
  fi
done

BOOTSTRAP=$(grep '^bootstrap.servers=' "$PROPS_FILE"               | cut -d= -f2- | tr -d ' \r\n')
TOPIC=$(grep '^checks_topic='          "$PROPS_FILE"               | cut -d= -f2- | tr -d ' \r\n')
TOKEN_URL=$(grep '^sasl.oauthbearer.token.endpoint.url=' "$PROPS_FILE" | cut -d= -f2- | tr -d ' \r\n')

# Extract OAuth credentials from sasl.jaas.config line.
# Handles both quoted (clientId="val") and unquoted (clientId=val) formats.
JAAS_LINE=$(grep '^sasl.jaas.config=' "$PROPS_FILE" | cut -d= -f2-)

extract_jaas() {
  local key="$1"
  echo "$JAAS_LINE" | awk -v k="$key" '{
    if (match($0, k "=\"[^\"]*\"")) {
      s = substr($0, RSTART, RLENGTH)
      gsub(k "=\"", "", s); gsub("\"", "", s); print s
    } else if (match($0, k "=[^ ;\"]*")) {
      s = substr($0, RSTART, RLENGTH)
      gsub(k "=", "", s); gsub(";", "", s); print s
    }
  }'
}

CLIENT_ID=$(extract_jaas "clientId")
CLIENT_SECRET=$(extract_jaas "clientSecret")
SCOPE=$(extract_jaas "scope")

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$SCOPE" ]]; then
  echo "ERROR: Could not extract clientId/clientSecret/scope from sasl.jaas.config"
  echo "JAAS: $JAAS_LINE"
  exit 1
fi

echo "==> bootstrap.servers=${BOOTSTRAP}"
echo "==> checks_topic=${TOPIC}"
echo "==> token_endpoint=${TOKEN_URL}"
echo "==> client_id=${CLIENT_ID}"

# -----------------------------------------------------------------------
# Step 1 — Acquire Entra ID OAuth JWT
# Azure EH accepts a raw JWT via SASL/PLAIN with username='$OAuth'
# -----------------------------------------------------------------------
echo ""
echo "==> [1] Acquiring Entra ID OAuth token ..."
TOKEN_RESP=$(curl -sS --max-time 30 -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "scope=${SCOPE}")

OAUTH_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || true)

if [[ -z "$OAUTH_TOKEN" ]]; then
  echo "FAIL: Could not acquire OAuth token"
  echo "Response: $TOKEN_RESP"
  exit 1
fi
echo "PASS: OAuth token acquired (length=${#OAUTH_TOKEN})"

# -----------------------------------------------------------------------
# Build a client.properties file for SASL/PLAIN with OAuth token
# Azure Event Hubs accepts:  username="$OAuth"  password=<JWT>
# This uses the standard Java Kafka client (no JAAS OAUTHBEARER complexity)
# -----------------------------------------------------------------------
PLAIN_PROPS="/tmp/kafka-plain-$$.properties"
cat > "$PLAIN_PROPS" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="\$OAuth" password="${OAUTH_TOKEN}";
# Force Kafka 2.x API format so SASL_AUTHENTICATE uses API v0 (no authBytes field)
# Azure Event Hubs responds with API v0 format which Kafka 3.x rejects by default.
api.version.request=false
api.version.fallback.ms=0
broker.version.fallback=2.0.0
EOF

# Unique consumer group per run
GROUP="kafka-check-$(date -u +%Y%m%dT%H%M%S)-$$"
MSG='{"check":"kafka-check","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "==> consumer.group=${GROUP}"
echo "==> using SASL/PLAIN with \$OAuth username + JWT password"
echo "==> image=${IMAGE}"

# -----------------------------------------------------------------------
# Step 2 — Auth check: list topics
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
# Step 3 — Produce a message
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
# Step 4 — Consume 1 message (unique group = fresh offset)
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

# Filter out log output; keep JSON payload line
JSON_LINE=$(echo "$CONSUMED" | grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*[A-Z\[]' | grep '^{' | head -1 || true)
if [[ -z "$JSON_LINE" ]]; then
  JSON_LINE=$(echo "$CONSUMED" | grep -v '^[[:space:]]*$' | tail -3 | grep '{' | head -1 || true)
fi

if [[ -z "$JSON_LINE" ]]; then
  echo "--- consumer output (for debugging) ---"
  echo "$CONSUMED"
  echo "--- end consumer output ---"
  echo "FAIL: No message consumed from '${TOPIC}' within timeout"
  exit 1
fi

echo "Consumed: $JSON_LINE"
echo "PASS: Produce + consume round-trip on '${TOPIC}' successful"
