output "client_properties" {
  description = "client.properties — single unified Confluent .properties file. Contains broker OAUTHBEARER + SR + JSON Schema serializers + consumer defaults."
  value       = local.client_properties
  sensitive   = true
}
