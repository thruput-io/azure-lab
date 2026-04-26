resource "azurerm_key_vault" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = var.sku_name
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
}

resource "azurerm_role_assignment" "deployer_certificates_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = var.deployer_object_id
}

resource "azurerm_role_assignment" "appgw_secrets_user" {
  count                = var.appgw_principal_id != null ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.appgw_principal_id
}

resource "azurerm_key_vault_certificate" "cert" {
  count        = (var.pfx_base64 != null && var.pfx_password != null) ? 1 : 0
  name         = "appgw-custom-cert"
  key_vault_id = azurerm_key_vault.this.id

  certificate {
    contents = var.pfx_base64
    password = var.pfx_password
  }

  depends_on = [azurerm_role_assignment.deployer_certificates_officer]
}
