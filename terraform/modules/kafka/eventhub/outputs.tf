output "namespace_id" {
  description = "Resource ID of the Event Hub namespace."
  value       = azurerm_eventhub_namespace.this.id
}

output "namespace_name" {
  description = "Name of the Event Hub namespace."
  value       = azurerm_eventhub_namespace.this.name
}

output "default_primary_connection_string" {
  description = "Primary connection string for the Event Hub namespace (SASL/PLAIN password)."
  value       = azurerm_eventhub_namespace.this.default_primary_connection_string
  sensitive   = true
}

output "private_ip_address" {
  description = "Private IP address of the Event Hub namespace private endpoint."
  value       = azurerm_private_endpoint.evh_pe.private_service_connection[0].private_ip_address
}



output "topic_names" {
  description = "Map of logical topic key to actual Event Hub topic name."
  value       = { for k, v in azurerm_eventhub.topics : k => v.name }
}
