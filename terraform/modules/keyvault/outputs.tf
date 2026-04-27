output "id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.this.name
}

output "uri" {
  description = "URI of the Key Vault (https://<name>.vault.azure.net/)."
  value       = azurerm_key_vault.this.vault_uri
}

output "cert_secret_id" {
  description = "Secret ID of the uploaded PFX certificate (null if no cert provided)."
  value       = length(azurerm_key_vault_certificate.cert) > 0 ? azurerm_key_vault_certificate.cert[0].secret_id : null
  depends_on  = [time_sleep.wait_for_appgw_rbac]
}

