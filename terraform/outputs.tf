output "key_vault_name" {
  description = "Name of the Key Vault used for client artifacts."
  value       = module.keyvault.name
}