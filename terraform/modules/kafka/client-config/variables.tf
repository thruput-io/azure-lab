variable "bootstrap_servers" {
  description = "Kafka bootstrap servers string (host:port)."
  type        = string
}

variable "client_id" {
  description = "Entra ID application (client) ID."
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Entra ID client secret value."
  type        = string
  sensitive   = true
}

variable "eventhub_scope" {
  description = "OAuth scope for the Event Hub namespace (https://<namespace>.servicebus.windows.net/.default)."
  type        = string
}

variable "token_endpoint_url" {
  description = "OAuth token endpoint URL (https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token)."
  type        = string
}

variable "schema_registry_url" {
  description = "Apicurio/Confluent-compatible Schema Registry URL (e.g. https://eventhub.example.com). When set, SR + serializer sections are added to client.properties."
  type        = string
  default     = null
}

variable "consumer_group_id" {
  description = "Kafka consumer group ID written into client.properties."
  type        = string
  default     = "default-consumer-group"
}

variable "sr_scope" {
  description = "OAuth scope for the Schema Registry (api://<apicurio-client-id>/.default)."
  type        = string
  default     = null
}


