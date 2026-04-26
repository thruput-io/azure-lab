# Helper module: writes a secret to an existing Key Vault and reads it back.
# Used by the keyvault integration test to verify read/write access.

variable "key_vault_id" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "secret_value" {
  type      = string
  sensitive = true
}

resource "azurerm_key_vault_secret" "test" {
  name         = var.secret_name
  value        = var.secret_value
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "readback" {
  name         = azurerm_key_vault_secret.test.name
  key_vault_id = var.key_vault_id
}

output "read_value" {
  description = "Value read back from Key Vault — must match secret_value."
  value       = data.azurerm_key_vault_secret.readback.value
  sensitive   = true
}
