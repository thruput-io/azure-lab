output "kafka_client_id" {
  description = "Client ID of the Kafka app registration owned by this module."
  value       = azuread_application.kafka_client.client_id
}

output "kafka_client_principal_id" {
  description = "Object ID of the Kafka client service principal (for external role assignments e.g. sr-admin)."
  value       = azuread_service_principal.kafka_client.object_id
}

output "namespace_id" {
  description = "Resource ID of the Event Hub namespace."
  value       = module.eventhub.namespace_id
}

output "namespace_name" {
  description = "Name of the Event Hub namespace."
  value       = module.eventhub.namespace_name
}

output "topic_names" {
  description = "Map of logical topic key to actual Event Hub topic name."
  value       = module.eventhub.topic_names
}

output "bootstrap_servers" {
  description = "Kafka bootstrap servers string (host:port). Use directly — do not extract from client files."
  value       = local.bootstrap_servers
}


output "client_properties" {
  description = "client.properties content — single unified Confluent .properties file (stored in Key Vault as 'client-properties')."
  value       = module.client_config.client_properties
  sensitive   = true
}
