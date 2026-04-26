# client-config — pure formatting module, zero Azure resources.
# Single source of truth for all Kafka client config file formats.
# Called by kafka/main.tf (stores to KV) and setup_e2e (writes local files).
# No extraction or conversion is ever done at call sites.
#
# Produces ONE canonical .properties file (client.properties) containing:
#   - Core connection (SASL_SSL + OAUTHBEARER)
#   - OIDC / Azure settings
#   - Schema Registry (when schema_registry_url is provided)
#   - JSON Schema serialization (key/value serializer + deserializer)
#   - Consumer defaults (group.id, auto.offset.reset)

locals {
  # ============================================================
  # client.properties — single unified Confluent .properties file.
  # Used by kafka-json-schema-console-producer/consumer and all
  # Java/Confluent tooling. SR section only rendered when
  # schema_registry_url is provided.
  # ============================================================
  sr_section = var.schema_registry_url != null ? join("\n", [
    "",
    "# --- SCHEMA REGISTRY ---",
    "schema.registry.url=${var.schema_registry_url}",
    "bearer.auth.issuer.endpoint.url=${var.token_endpoint_url}",
    "bearer.auth.client.id=${var.client_id}",
    "bearer.auth.client.secret=${var.client_secret}",
    "bearer.auth.scope=${var.sr_scope}",
    "",
    "# --- JSON SCHEMA SERIALIZATION ---",
    "key.serializer=org.apache.kafka.common.serialization.StringSerializer",
    "value.serializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer",
    "",
    "key.deserializer=org.apache.kafka.common.serialization.StringDeserializer",
    "value.deserializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializer",
  ]) : ""

  client_properties = join("\n", [
    "# --- CORE CONNECTION ---",
    "bootstrap.servers=${var.bootstrap_servers}",
    "security.protocol=SASL_SSL",
    "sasl.mechanism=OAUTHBEARER",
    "",
    "# --- OIDC / AZURE SETTINGS ---",
    "sasl.oauthbearer.method=oidc",
    "sasl.oauthbearer.client.id=${var.client_id}",
    "sasl.oauthbearer.client.secret=${var.client_secret}",
    "sasl.oauthbearer.scope=${var.eventhub_scope}",
    "sasl.oauthbearer.token.endpoint.url=${var.token_endpoint_url}",
    local.sr_section,
    "",
    "# --- CONSUMER SPECIFIC ---",
    "group.id=${var.consumer_group_id}",
    "auto.offset.reset=earliest",
  ])
}
