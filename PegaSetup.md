# Pega Integration Guide

This guide describes how to connect a **Pega Platform** application to Azure Event Hubs (Kafka endpoint) exposed through Application Gateway.

## Prerequisites

- **Pega Platform 24.1.3 or later** (required for `SASL/OAUTHBEARER`)
- The populated `client.properties` file from **Actions → Download client.properties → Run workflow**

---

## Step 1 — Create a Kafka Configuration Rule

In **Pega Designer Studio**:

1. Navigate to **Records → Integration-Resources → Kafka Configuration**.
2. Create a rule (for example `EventHubKafkaConfig`).
3. Set **Bootstrap servers** to `<CUSTOM_DOMAIN_NAME>:9093`.
4. Under **Additional client properties**, upload/paste the downloaded `client.properties`.

Expected authentication properties:

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

---

## Step 2 — Create a Kafka Data Set Rule

1. Navigate to **Records → Integration-Resources → Data Set**.
2. Create a **Kafka** data set (for example `OrderPlacedDataSet`).
3. Set **Kafka Configuration** to `EventHubKafkaConfig`.
4. Set **Topic** to `orders.placed`.
5. Set **Message format** to a format supported by your Pega model (for example JSON/Text).

---

## Step 3 — Turnaround Test

Produce a test message and verify Pega can consume it.

Example producer payload:

```json
{"order_id":"pega-test-123","product":"turnaround","quantity":1,"timestamp":1713648000000}
```

Verify in Pega:

- The record appears in Data Set browse/run.
- Fields map correctly in your target data class.
- No Kafka consumer/authentication errors are logged.

> Tip: If no records appear, check consumer offset settings (`latest` vs `earliest`).

---

## Compatibility Summary

| Item | Status | Notes |
|---|---|---|
| Kafka broker (`SASL/OAUTHBEARER`) | ✅ Supported | Requires Pega `24.1.3+` |
| Bootstrap via App Gateway `:9093` | ✅ Supported | SNI must match `CUSTOM_DOMAIN_NAME` |
| `client.properties` file | ✅ Native | Pega can import/paste additional properties |

---

## Retrieving Credentials

Run **Actions → Download client.properties → Run workflow**. The workflow uploads `client.properties` as an artifact.
