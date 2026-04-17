resource "random_id" "kvname" {
  byte_length = 4
}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-lab-${random_id.kvname.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = true
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "appgw_id" {
  name                = "id-appgw-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Grant Managed Identity access to KV
resource "azurerm_role_assignment" "appgw_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw_id.principal_id
}

# Grant the deploying user (CI/CD) access to KV to import certs
resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
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
