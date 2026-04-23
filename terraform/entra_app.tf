# --- App Registration ---
resource "azuread_application" "kafka_client" {
  display_name = "app-eventhub-kafka-client"
}

resource "azuread_service_principal" "kafka_client" {
  client_id = azuread_application.kafka_client.client_id
}

resource "azuread_application_password" "kafka_client_secret" {
  application_id = azuread_application.kafka_client.id
  display_name   = "kafka-client-secret"
  end_date       = "2026-12-31T00:00:00Z"
}

# --- RBAC: Event Hub Data Sender (produce) ---
resource "azurerm_role_assignment" "kafka_client_sender" {
  scope                = azurerm_eventhub_namespace.evh.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

# --- RBAC: Event Hub Data Receiver (consume) ---
resource "azurerm_role_assignment" "kafka_client_receiver" {
  scope                = azurerm_eventhub_namespace.evh.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

# --- RBAC: Schema Registry Reader ---
resource "azurerm_role_assignment" "kafka_client_sr_reader" {
  scope                = azurerm_eventhub_namespace.evh.id
  role_definition_name = "Schema Registry Reader"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

# --- RBAC: Schema Registry Contributor (to register schemas) ---
resource "azurerm_role_assignment" "kafka_client_sr_contributor" {
  scope                = azurerm_eventhub_namespace.evh.id
  role_definition_name = "Schema Registry Contributor"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

# --- Store client secret in Key Vault ---
resource "azurerm_key_vault_secret" "kafka_client_secret" {
  name            = "kafka-client-secret"
  value           = azuread_application_password.kafka_client_secret.value
  key_vault_id    = azurerm_key_vault.kv.id
  expiration_date = "2026-12-31T00:00:00Z"

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

# --- Store rendered client.properties in Key Vault for team retrieval ---
# Kafka broker: App Gateway (port 9093), SASL/PLAIN with $ConnectionString.
# This file is the single source of truth for Kafka connectivity.
resource "azurerm_key_vault_secret" "kafka_client_properties" {
  name         = "kafka-client-properties"
  key_vault_id = azurerm_key_vault.kv.id
  value = join("\n", [
    "# ============================================================",
    "# Kafka broker — via Application Gateway (public endpoint)",
    "# SASL/PLAIN with $ConnectionString (Azure Event Hubs for Kafka)",
    "# ============================================================",
    "bootstrap.servers=${var.custom_domain_name}:9093",
    "security.protocol=SASL_SSL",
    "sasl.mechanism=PLAIN",
    "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$ConnectionString\" password=\"${azurerm_eventhub_namespace.evh.default_primary_connection_string}\";",
    "",
    "# ============================================================",
    "# Topics",
    "# ============================================================",
    "topic=${azurerm_eventhub.orders_topic.name}",
    "checks_topic=${azurerm_eventhub.checks_topic.name}",
  ])

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

# --- Store rendered schema-client.properties in Key Vault ---
# Self-contained properties for Avro clients: Kafka broker + SR URL + OAuth.
resource "azurerm_key_vault_secret" "schema_client_properties" {
  name         = "schema-client-properties"
  key_vault_id = azurerm_key_vault.kv.id
  value = join("\n", [
    "# ============================================================",
    "# Kafka broker (needed by Avro producer/consumer)",
    "# ============================================================",
    "bootstrap.servers=${var.custom_domain_name}:9093",
    "security.protocol=SASL_SSL",
    "sasl.mechanism=PLAIN",
    "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$ConnectionString\" password=\"${azurerm_eventhub_namespace.evh.default_primary_connection_string}\";",
    "",
    "# ============================================================",
    "# Schema Registry (Confluent-compatible API via App Gateway)",
    "# ============================================================",
    "schema.registry.url=https://${var.custom_domain_name}",
    "",
    "# ============================================================",
    "# OAuth credentials (Entra ID — used by client for SR auth)",
    "# ============================================================",
    "oauth.token.endpoint.url=https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/oauth2/v2.0/token",
    "oauth.client.id=${azuread_application.kafka_client.client_id}",
    "oauth.client.secret=${azuread_application_password.kafka_client_secret.value}",
  ])

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

# --- Outputs ---
output "kafka_client_id" {
  value = azuread_application.kafka_client.client_id
}

output "kafka_client_secret" {
  value     = azuread_application_password.kafka_client_secret.value
  sensitive = true
}

output "kafka_bootstrap_server" {
  value = "${var.custom_domain_name}:9093"
}

output "schema_registry_endpoint" {
  value = "https://${var.custom_domain_name}"
}

output "checks_topic" {
  value = azurerm_eventhub.checks_topic.name
}

output "orders_topic" {
  value = azurerm_eventhub.orders_topic.name
}
