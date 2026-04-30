# Helper module: creates RG, VNet, subnets, and service principal for eventhub integration tests.

variable "location" {
  type    = string
  default = "East US"
}

resource "random_id" "suffix" {
  byte_length = 3
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "test" {
  name     = "rg-evh-inttest-${random_id.suffix.hex}"
  location = var.location
}

resource "azurerm_virtual_network" "test" {
  name                = "vnet-evh-inttest-${random_id.suffix.hex}"
  address_space       = ["10.10.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.10.2.0/24"]
}

resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw-inttest-${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = azurerm_resource_group.test.name
}

output "namespace_name" {
  value = "evh-inttest-${random_id.suffix.hex}"
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "pe_subnet_id" {
  value = azurerm_subnet.pe.id
}

output "vnet_id" {
  value = azurerm_virtual_network.test.id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "client_id" {
  value = data.azurerm_client_config.current.client_id
}

# client_secret must be supplied via TF_VAR_client_secret env var at test runtime
variable "client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

output "client_secret" {
  value     = var.client_secret
  sensitive = true
}

resource "azurerm_key_vault" "test" {
  name                       = "kv-evh-it-${random_id.suffix.hex}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.test.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.test.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_cert_officer" {
  scope                = azurerm_key_vault.test.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_certificate" "appgw_tls" {
  name         = "appgw-tls-inttest"
  key_vault_id = azurerm_key_vault.test.id

  certificate_policy {
    issuer_parameters { name = "Self" }
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }
    lifetime_action {
      action { action_type = "AutoRenew" }
      trigger { days_before_expiry = 30 }
    }
    secret_properties { content_type = "application/x-pkcs12" }
    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]
      key_usage          = ["digitalSignature", "keyEncipherment"]
      subject            = "CN=inttest.local"
      validity_in_months = 12
    }
  }

  depends_on = [azurerm_role_assignment.kv_cert_officer]
}

output "key_vault_id" {
  value = azurerm_key_vault.test.id
}

output "appgw_subnet_id" {
  value = azurerm_subnet.appgw.id
}

output "appgw_identity_id" {
  value = azurerm_user_assigned_identity.appgw.id
}

output "kv_cert_secret_id" {
  value = azurerm_key_vault_certificate.appgw_tls.secret_id
}
