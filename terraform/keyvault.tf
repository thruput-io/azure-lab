resource "random_id" "kvname" {
  byte_length = 4
}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-lab-${random_id.kvname.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  rbac_authorization_enabled  = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "appgw_id" {
  name                = "id-appgw-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "appgw_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw_id.principal_id
}

resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

resource "azurerm_key_vault_certificate" "custom_cert" {
  name         = "appgw-custom-cert"
  key_vault_id = azurerm_key_vault.kv.id

  certificate {
    contents = var.pfx_base64
    password = var.pfx_password
  }

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}
