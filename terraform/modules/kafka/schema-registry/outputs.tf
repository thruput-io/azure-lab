output "fqdn" {
  description = "Fully qualified domain name of the Apicurio container group."
  value       = azurerm_container_group.apicurio.fqdn
}

output "ip_address" {
  description = "Public IP address of the Apicurio container group."
  value       = azurerm_container_group.apicurio.ip_address
}

output "ccompat_url" {
  description = "Confluent-compatible Schema Registry base URL."
  value       = "http://${azurerm_container_group.apicurio.fqdn}:8080/apis/ccompat/v7"
}

output "principal_id" {
  description = "Principal ID of the container group system-assigned managed identity (for AcrPull role assignment)."
  value       = azurerm_container_group.apicurio.identity[0].principal_id
}
