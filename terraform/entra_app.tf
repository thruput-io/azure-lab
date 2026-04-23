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
    "schema.registry.url=https://${var.custom_domain_name}/apis/ccompat/v7",
    "",
    "# ============================================================",
    "# OAuth credentials (Entra ID — used by client for SR auth)",
    "# ============================================================",
    "oauth.token.endpoint.url=https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/oauth2/v2.0/token",
    "oauth.client.id=${azuread_application.kafka_client.client_id}",
    "oauth.client.secret=${azuread_application_password.kafka_client_secret.value}",
    "oauth.scope=api://${azuread_application.apicurio.client_id}/Registry.Access",
  ])

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

# --- Apicurio App Registration ---
resource "azuread_application" "apicurio" {
  display_name     = "app-apicurio-registry"
  identifier_uris  = ["api://app-apicurio-registry-${data.azurerm_client_config.current.client_id}"]

  app_role {
    allowed_member_types = ["Application", "User"]
    description          = "Full administrative access to the registry."
    display_name         = "sr-admin"
    enabled              = true
    id                   = "49666f21-169b-4408-8924-f58479e0802c"
    value                = "sr-admin"
  }

  app_role {
    allowed_member_types = ["Application", "User"]
    description          = "Read-only access to the registry."
    display_name         = "sr-readonly"
    enabled              = true
    id                   = "f310f3c5-849c-47a3-b40e-6f8e77a16f0d"
    value                = "sr-readonly"
  }

  api {
    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access the registry."
      admin_consent_display_name = "Access Registry"
      enabled                    = true
      id                         = "1e0c40e5-7b56-4c92-95f0-621e25e1a3c7"
      type                       = "User"
      user_consent_description   = "Allow the application to access the registry on your behalf."
      user_consent_display_name  = "Access Registry"
      value                      = "Registry.Access"
    }
  }
}

resource "azuread_service_principal" "apicurio" {
  client_id = azuread_application.apicurio.client_id
}

# --- Assign Admin role to Kafka Client (so it can register schemas) ---
resource "azuread_app_role_assignment" "kafka_client_apicurio_admin" {
  app_role_id         = { for r in azuread_application.apicurio.app_role : r.display_name => r.id }["sr-admin"]
  principal_object_id = azuread_service_principal.kafka_client.object_id
  resource_object_id  = azuread_service_principal.apicurio.object_id
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
