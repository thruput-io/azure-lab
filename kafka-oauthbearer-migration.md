# Kafka SASL/OAUTHBEARER Migration Plan

> **Save location: project root (`kafka-oauthbearer-migration.md`)**
> **Status: CLOSED — Azure Event Hubs does not support SASL/OAUTHBEARER on the Kafka endpoint. See findings below.**

---

## Why this plan exists

The current `kafka-client.properties` uses **SASL/PLAIN with `$ConnectionString`** for Kafka broker auth:

```properties
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required
  username="$ConnectionString" password="<primary-connection-string>";
```

This is an **Azure-proprietary shortcut**. It works, but:

- It requires sharing the Event Hub namespace primary key (connection string) with external clients
- It is **not** how a standard Confluent KafkaSerdes client (`kafka-avro-serializer`) authenticates
- Pega's standard Confluent client configuration uses SASL/OAUTHBEARER with OAuth2 client credentials

The original `confluent-endpoint-check.yml` (commit `1561196`) already had the correct approach:

```properties
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required
  clientId="<id>" clientSecret="<secret>" scope="https://eventhubs.azure.net/.default";
```

This is pure OAuth2 client credentials — standard Confluent KafkaSerdes properties, no Azure-specific shortcut.

---

## Goal

Replace SASL/PLAIN + `$ConnectionString` with **SASL/OAUTHBEARER + Entra ID client credentials**
in both `kafka-client.properties` and `schema-client.properties`.

After this change:
- No connection string is shared with external clients
- Both properties files use only OAuth2 client credentials (client_id + client_secret + token endpoint)
- The configuration is valid for standard Confluent KafkaSerdes (`kafka-avro-serializer` / `kafka-avro-deserializer`)
- Pega can use the properties file directly with their standard Confluent client

---

## What already exists (no new Terraform resources needed)

The `kafka_client` app registration already has:
- `Azure Event Hubs Data Sender` role on the namespace → produce
- `Azure Event Hubs Data Receiver` role on the namespace → consume
- A client secret stored in Key Vault (`kafka-client-secret`)

The OAuth scope for Event Hubs is the standard Azure scope: `https://eventhubs.azure.net/.default`

No new app registrations, no new role assignments, no new secrets.

---

## Constraint (from `goals.md`)

> There is no value in setting up, testing, or documenting any schema registry feature,
> authentication flow, or client configuration that is **not supported by Confluent KafkaSerdes
> with schema support** (`kafka-avro-serializer` / `kafka-avro-deserializer`).

SASL/OAUTHBEARER with `OAuthBearerLoginCallbackHandler` is the standard Confluent KafkaSerdes
OAuth mechanism. SASL/PLAIN with `$ConnectionString` is not.

---

## Target properties

### `kafka-client.properties` (after migration)

```properties
bootstrap.servers=<domain>:9093
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/<tenant_id>/oauth2/v2.0/token
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId="<kafka_client_app_id>" clientSecret="<secret>" scope="https://eventhubs.azure.net/.default";

topic=<orders_topic>
checks_topic=<checks_topic>
```

### `schema-client.properties` Kafka section (after migration)

Same OAUTHBEARER block as above — replaces the current SASL/PLAIN block.
The `bearer.auth.*` Schema Registry section is unchanged.

---

## ⛔ Findings — Plan Closed

Step 1 (local Docker test) was completed on 2026-04-24. Result: **SASL/OAUTHBEARER is not supported by Azure Event Hubs on port 9093.**

The broker accepts the TCP/TLS connection but rejects the OAUTHBEARER SASL exchange at the protocol level:
```
java.lang.RuntimeException: non-nullable field authBytes was serialized as null
    at SaslAuthenticateResponseData.read(...)
```
This means the broker returns a malformed/empty auth response because it does not implement the OAUTHBEARER SASL mechanism on the Kafka endpoint.

Azure Event Hubs Kafka endpoint (port 9093) supports **only SASL/PLAIN with `$ConnectionString`**. OAuth is only available via AMQP (port 5671) — a different protocol that Confluent KafkaSerdes does not use.

The original `confluent-endpoint-check.yml` (commit `1561196`) that used OAUTHBEARER was written with the right intent but was never actually working at the broker auth level.

**Consequence:** The current SASL/PLAIN + `$ConnectionString` approach is not a shortcut or a workaround — it is the **only supported Kafka auth mechanism for Azure Event Hubs**. It must remain in both `kafka-client.properties` and `schema-client.properties`.

This plan is closed. No Terraform changes are needed.

---

## Original Implementation Steps (for reference)

### Step 1 — Verify OAUTHBEARER works via local Docker test

**Before touching any Terraform**, confirm that `kafka-console-producer/consumer` from
`confluentinc/cp-kafka:8.2.0` can authenticate to Event Hubs using OAUTHBEARER.

Use a runtime properties file (from "Download client.properties" workflow artifact) as the
base, but temporarily override the SASL section for the Docker test only.

Test command:
```bash
echo '{"check":"oauthbearer-test"}' | docker run --rm -i \
  -v /path/to/test.properties:/tmp/client.properties:ro \
  confluentinc/cp-kafka:8.2.0 \
  kafka-console-producer \
    --bootstrap-server eventhub.grayskull.se:9093 \
    --topic <checks_topic> \
    --producer.config /tmp/client.properties
```

Where `test.properties` contains the OAUTHBEARER block above with real values.

**If it works** → proceed to Step 2.

**If it fails** → investigate. Common issues:
- Missing `sasl.oauthbearer.allowed.urls` JVM property (may need `-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=https://login.microsoftonline.com`)
- Wrong scope (must be `https://eventhubs.azure.net/.default`, not `api://...`)
- Token endpoint URL format

Any fix goes into `entra_app.tf` (the properties content). **Not into the script.**

**Verification:** Producer and consumer succeed with OAUTHBEARER. No `$ConnectionString` used.

---

### Step 2 — Update `entra_app.tf`

Replace the SASL/PLAIN block in both KV secrets:

**In `kafka-client-properties`:** Replace `PlainLoginModule` block with `OAuthBearerLoginModule` block.

**In `schema-client-properties`:** Replace `PlainLoginModule` block with `OAuthBearerLoginModule` block.
The `bearer.auth.*` SR section is unchanged.

The `sasl.oauthbearer.token.endpoint.url` value:
```
https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/oauth2/v2.0/token
```

The `sasl.jaas.config` value:
```
org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId="${azuread_application.kafka_client.client_id}" clientSecret="${azuread_application_password.kafka_client_secret.value}" scope="https://eventhubs.azure.net/.default";
```

**Verification:** `terraform plan` shows only the two KV secret values changing. No new resources.

---

### Step 3 — Update `kafka-check.sh`

The required keys validation loop must be updated — `sasl.jaas.config` stays required but
`sasl.mechanism` changes from `PLAIN` to `OAUTHBEARER`. No other script changes needed.

Also add `sasl.login.callback.handler.class` and `sasl.oauthbearer.token.endpoint.url` to
the required keys list so the script validates the file is complete.

**Verification:** `bash -n scripts/kafka-check.sh` passes. Required keys list matches the
new properties file content.

---

### Step 4 — Deploy and run Kafka Tests

Push Terraform change. `deploy.yml` will update both GitHub secrets
(`KAFKA_CLIENT_PROPERTIES`, `SCHEMA_CLIENT_PROPERTIES`) from Key Vault post-deploy.

Run `Kafka Tests` workflow — must pass all checks:
- Check 2: Auth (topic list) ✅
- Check 3: Produce ✅
- Check 4: Consume ✅

**Verification:** All checks green. No `$ConnectionString` or `PlainLoginModule` in logs.

---

### Step 5 — Run Schema Tests

Run `Schema Tests` workflow — must still pass all checks:
- Check 1: Connectivity + SSL ✅
- Check 2: Authentication (OAuth + Kafka) ✅
- Check 3: Avro Produce + Consume ✅

**Verification:** All checks green. Both Kafka OAUTHBEARER and SR bearer.auth.* OAuth working.

---

## Rules for AI agents working on this plan

1. **Read `project_guidelines.md` before starting each step.**

2. **Step 1 is mandatory.** Do not update `entra_app.tf` until OAUTHBEARER is confirmed
   working via local Docker test. If it fails, fix the properties content (in `entra_app.tf`)
   and retest — do not add workarounds to scripts.

3. **Do not create local `.properties` files.** Step 1 requires a runtime properties file.
   If you don't have one, ask the user to run "Download client.properties" and share the artifact.

4. **The `$ConnectionString` must be completely removed** from both KV secrets after this
   migration. It must not appear in any properties file, script, or workflow.

5. **Do not update this plan during implementation.** Record deviations in `deviations.md`.

---

## Process Rules

- Each step is a separate commit with its own verification point.
- Before merging, re-read `project_guidelines.md` and this file.
- Docker testing is read-only from the repo's perspective — findings flow back only as
  `entra_app.tf` changes.
