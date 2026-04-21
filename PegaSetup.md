# Pega Integration Guide

This guide describes how to connect a **Pega Platform** application to the Azure Event Hub exposed via Application Gateway using the Kafka Data Set feature.

## Prerequisites

- **Pega Platform 24.1.3 or later** — required for SASL/OAUTHBEARER support
- The populated `client.properties` file — retrieve it via **Actions → Download client.properties → Run workflow**

---

## Step 1 — Create a Kafka Configuration Rule

In **Pega Designer Studio**:

1. Navigate to **Records → Integration-Resources → Kafka Configuration**
2. Create a new rule (e.g. `EventHubKafkaConfig`)
3. Set **Bootstrap servers**: `<CUSTOM_DOMAIN_NAME>:9093` (use the same domain configured in `CUSTOM_DOMAIN_NAME`)
4. Under **Additional client properties**, upload or paste the contents of `client.properties`

The relevant properties Pega reads from `client.properties`:

```properties
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
  clientId="<CLIENT_ID>" \
  clientSecret="<CLIENT_SECRET>" \
  scope="https://eventhubs.azure.net/.default";
```

> These properties are supported from **Pega 24.1.3+**. Earlier versions will fail with "No principal name in JWT claim".

---

## Step 2 — Create an Avro Schema Rule

Pega manages Schema Registry configuration separately from the Kafka broker config. 

1. Navigate to **Records → Integration-Resources → Avro Schema**
2. Create a new rule (e.g. `OrderPlacedAvroSchema`)
3. Set **Schema Registry URL**: `https://<CUSTOM_DOMAIN_NAME>:8081`
4. Set **Authentication**: Basic Auth
   - **Username**: `<CLIENT_ID>` (from the downloaded `client.properties` — value of `schema.registry.basic.auth.user.info` before the `:`)
   - **Password**: `<CLIENT_SECRET>` (from the downloaded `client.properties`)
5. Set **Schema subject**: `orders.placed-value`
6. Click **Retrieve schema** — Pega fetches the Avro schema from the Schema Registry and populates the field list automatically

> **No manual schema entry needed.** As long as the Schema Registry URL, credentials, and subject are correct, Pega imports the schema in one click. The schema for `orders.placed-value` is:

```json
{
  "type": "record",
  "name": "OrderPlaced",
  "namespace": "se.thruput.orders",
  "fields": [
    { "name": "order_id",  "type": "string" },
    { "name": "product",   "type": "string" },
    { "name": "quantity",  "type": "int"    },
    { "name": "timestamp", "type": "long"   }
  ]
}
```

---

## Step 3 — Create a Kafka Data Set Rule

1. Navigate to **Records → Integration-Resources → Data Set**
2. Create a new rule of type **Kafka** (e.g. `OrderPlacedDataSet`)
3. Set **Kafka Configuration**: `EventHubKafkaConfig` (from Step 1)
4. Set **Topic**: `orders.placed`
5. Set **Message format**: `Avro`
6. Set **Avro Schema rule**: `OrderPlacedAvroSchema` (from Step 2)
---

## Step 4 — Map the Avro Schema to a Pega Data Class

1. Create a **Data class** in Pega matching the `OrderPlaced` Avro record fields:

   | Pega Property | Avro Field  | Type            |
   |---------------|-------------|-----------------|
   | `order_id`    | `order_id`  | Text            |
   | `product`     | `product`   | Text            |
   | `quantity`    | `quantity`  | Integer         |
   | `timestamp`   | `timestamp` | Long / DateTime |

2. In the Kafka Data Set rule, map the Avro schema fields to the Pega class properties.

---

## Step 5 — Turnaround Test (Produce a Message for Pega to Consume)

Before wiring up a full Pega case or flow, verify the end-to-end path by producing a known test message to the `orders.placed` topic. Pega can then consume it and you can confirm the fields are correctly deserialized.

### Option A — GitHub Actions (recommended)

Run the **Confluent Endpoint Check** workflow — it produces one Avro message with a known `order_id` and `timestamp`:

**Actions → Confluent Endpoint Check → Run workflow**

After the workflow completes, trigger a **Browse** or **Run** on the `OrderPlacedDataSet` in Pega. You should see a record with:

| Field       | Expected value                                    |
|-------------|---------------------------------------------------|
| `order_id`  | `check-<timestamp>` (e.g. `check-1713648000000`)  |
| `product`   | `endpoint-check`                                  |
| `quantity`  | `1`                                               |
| `timestamp` | milliseconds epoch matching the workflow run time |

### Option B — Local CLI (using `client.properties`)

1. Download the populated `client.properties` via **Actions → Download client.properties → Run workflow**
2. Run the Confluent Docker image locally:

```bash
PROPS="$(pwd)/client.properties"
TOPIC="orders.placed"
TS=$(date +%s%3N)

docker run --rm \
  -v "$PROPS:/etc/kafka/client.properties:ro" \
  -e TOPIC="$TOPIC" \
  -e TS="$TS" \
  confluentinc/cp-schema-registry:7.6.0 \
  bash -c '
    echo "{\"order_id\":\"pega-test-$TS\",\"product\":\"turnaround\",\"quantity\":1,\"timestamp\":$TS}" | \
    kafka-avro-console-producer \
      --broker-list "$(grep "^bootstrap.servers" /etc/kafka/client.properties | cut -d= -f2-)" \
      --topic "$TOPIC" \
      --producer.config /etc/kafka/client.properties
  '
echo "Produced message with order_id=pega-test-$TS"
```

3. In Pega, browse the `OrderPlacedDataSet` — you should see the record with `order_id=pega-test-<timestamp>`.

### What to verify in Pega

- The record appears in the Data Set browse view
- All four fields (`order_id`, `product`, `quantity`, `timestamp`) are populated correctly
- No deserialization errors in the Pega logs (`prpcServiceThread` / Kafka consumer logs)

> **Tip**: If the record does not appear, check that the Kafka Data Set consumer group offset is set to read from the **latest** offset (not earliest), or temporarily set it to `earliest` to catch messages already in the topic.

---

## Compatibility Summary

| Item                                     | Status      | Notes                                                            |
|------------------------------------------|-------------|------------------------------------------------------------------|
| Kafka broker (SASL/OAUTHBEARER)          | ✅ Supported | Requires Pega **24.1.3+**                                        |
| Bootstrap server via App Gateway `:9093` | ✅ Supported | L4 TLS proxy — SNI must match your `CUSTOM_DOMAIN_NAME` value    |
| Avro message format                      | ✅ Supported | Pega 8.7+                                                        |
| Schema Registry URL (HTTPS `:8081`)      | ✅ Supported | Configure in Avro Schema rule                                    |
| Schema Registry Basic Auth               | ✅ Supported | Pega 8.7.6+                                                      |
| TopicNameStrategy (default)              | ✅ Default   | No extra configuration needed — subject is `orders.placed-value` |
| `client.properties` file                 | ✅ Native    | Pega reads this directly in the Kafka Configuration rule         |

---

## Retrieving Credentials

Run the **Actions → Download client.properties → Run workflow** GitHub Actions workflow. The populated `client.properties` file (with all credentials injected) is uploaded as a build artifact with a 10-day retention period.

The `client.properties` file contains everything needed — bootstrap server, SASL credentials, and Schema Registry settings.
