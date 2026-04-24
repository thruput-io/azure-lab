# Deviations & Findings

Records deliberate deviations from plans and key findings from investigations.

---

## DEV-001 — SASL/PLAIN + `$ConnectionString` is the only supported Kafka auth on Azure Event Hubs

**Date:** 2026-04-24  
**Plan:** `kafka-oauthbearer-migration.md`  
**Status:** Plan closed — no change needed

### Finding

Azure Event Hubs Kafka endpoint (port 9093) does **not** support SASL/OAUTHBEARER.

Tested via local Docker (`confluentinc/cp-kafka:8.2.0`) with correct OAUTHBEARER config:
- `sasl.mechanism=OAUTHBEARER`
- `sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler`
- `sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/.../oauth2/v2.0/token`
- `sasl.jaas.config=OAuthBearerLoginModule required clientId=... clientSecret=... scope="https://eventhubs.azure.net/.default";`

The OAuth token was acquired successfully from Entra ID. The broker accepted the TCP/TLS
connection but rejected the SASL exchange:

```
java.lang.RuntimeException: non-nullable field authBytes was serialized as null
    at SaslAuthenticateResponseData.read(...)
```

The broker returns a malformed/empty SASL auth response because it does not implement the
OAUTHBEARER mechanism on the Kafka protocol endpoint.

### Consequence

**SASL/PLAIN with `$ConnectionString` is not a shortcut — it is the only supported Kafka
auth mechanism for Azure Event Hubs.** It must remain in both `kafka-client.properties` and
`schema-client.properties`. This is an Azure platform constraint, not a configuration issue.

OAuth on Event Hubs is only available via AMQP (port 5671), which Confluent KafkaSerdes
does not use.

### Impact on Pega

Pega's Confluent KafkaSerdes client must use SASL/PLAIN with `$ConnectionString`. This is
a standard Confluent client mechanism — `PlainLoginModule` with `username="$ConnectionString"`
is well-documented for Azure Event Hubs + Confluent clients. It is not Azure-proprietary in
the sense that it breaks standard clients — it is the documented integration pattern.

---
