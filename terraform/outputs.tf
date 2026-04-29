output "key_vault_name" {
  description = "Name of the Key Vault used for client artifacts."
  value       = module.keyvault.name
}

output "client_properties" {
  description = "Canonical Java client.properties artifact content."
  value       = module.kafka.client_properties
  sensitive   = true
}