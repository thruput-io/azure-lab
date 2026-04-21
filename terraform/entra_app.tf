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

# --- RBAC: Schema Registry Contributor ---
resource "azurerm_role_assignment" "kafka_client_schema_registry" {
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
resource "azurerm_key_vault_secret" "kafka_client_properties" {
  name         = "kafka-client-properties"
  key_vault_id = azurerm_key_vault.kv.id
  value = join("\n", [
    "bootstrap.servers=${var.custom_domain_name}:9093",
    "security.protocol=SASL_SSL",
    "sasl.mechanism=OAUTHBEARER",
    "sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler",
    "sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/oauth2/v2.0/token",
    "sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId=\"${azuread_application.kafka_client.client_id}\" clientSecret=\"${azuread_application_password.kafka_client_secret.value}\" scope=\"https://eventhubs.azure.net/.default\";",
    "schema.registry.url=https://${var.custom_domain_name}",
    "basic.auth.credentials.source=USER_INFO",
    "schema.registry.basic.auth.user.info=${azuread_application.kafka_client.client_id}:${azuread_application_password.kafka_client_secret.value}",
    "value.serializer=io.confluent.kafka.serializers.KafkaAvroSerializer",
    "value.deserializer=io.confluent.kafka.serializers.KafkaAvroDeserializer",
    "specific.avro.reader=true",
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

output "schema_registry_url" {
  value = "https://${var.custom_domain_name}"
}
