# ============================================================
# Identity — app registration owned by this module.
# Convention: display name = "app-kafka-<namespace_name>"
# ============================================================
resource "azuread_application" "kafka_client" {
  display_name = "app-kafka-${var.namespace_name}"
}

resource "azuread_service_principal" "kafka_client" {
  client_id = azuread_application.kafka_client.client_id
}

resource "azuread_application_password" "kafka_client" {
  application_id = azuread_application.kafka_client.id
  display_name   = "kafka-client-secret"
  end_date       = "2026-12-31T00:00:00Z"
}

# ============================================================
# Event Hub namespace
# ============================================================
module "eventhub" {
  source = "./eventhub"

  namespace_name      = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  pe_subnet_id        = var.pe_subnet_id
  vnet_id             = var.vnet_id
  topics              = var.topics
}

# ============================================================
# RBAC — grant the kafka client identity produce + consume
# on the namespace this module owns.
# ============================================================
resource "azurerm_role_assignment" "kafka_client_sender" {
  scope                = module.eventhub.namespace_id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

resource "azurerm_role_assignment" "kafka_client_receiver" {
  scope                = module.eventhub.namespace_id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azuread_service_principal.kafka_client.object_id
}

# ============================================================
# Store raw client secret in Key Vault.
# Convention: secret name = "kafka-client-secret"
# ============================================================
resource "azurerm_key_vault_secret" "kafka_client_secret" {
  name            = "kafka-client-secret"
  value           = azuread_application_password.kafka_client.value
  key_vault_id    = var.key_vault_id
  expiration_date = "2026-12-31T00:00:00Z"
}

# ============================================================
# Derived values — by convention, never passed from outside.
# ============================================================
locals {
  bootstrap_servers  = "${var.custom_domain_name}:9093"
  eventhub_scope     = "https://${var.namespace_name}.servicebus.windows.net/.default"
  token_endpoint_url = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
  client_id          = azuread_application.kafka_client.client_id
  client_secret      = azuread_application_password.kafka_client.value
}

# ============================================================
# client-config — single source of truth for all file formats.
# Formatting lives here; kafka/main.tf only stores the outputs.
# ============================================================
module "client_config" {
  source = "./client-config"

  bootstrap_servers   = local.bootstrap_servers
  client_id           = local.client_id
  client_secret       = local.client_secret
  eventhub_scope      = local.eventhub_scope
  token_endpoint_url  = local.token_endpoint_url
  schema_registry_url = var.schema_registry_url
  sr_scope            = var.sr_scope
  consumer_group_id   = var.consumer_group_id
}

# ============================================================
# Client config files — stored in Key Vault.
# Values come exclusively from module.client_config outputs.
# ============================================================
resource "azurerm_key_vault_secret" "client_properties" {
  name         = "client-properties"
  key_vault_id = var.key_vault_id
  value        = module.client_config.client_properties
  content_type = "text/x-java-properties"
}
