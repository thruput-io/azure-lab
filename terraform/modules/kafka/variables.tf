variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "namespace_name" {
  description = "Event Hub namespace name."
  type        = string
}

variable "pe_subnet_id" {
  description = "Subnet ID for the Event Hub private endpoint."
  type        = string
}

variable "vnet_id" {
  description = "Virtual network ID for the private DNS zone link."
  type        = string
}

variable "topics" {
  description = "Map of Event Hub topics to create."
  type = map(object({
    name              = string
    partition_count   = number
    message_retention = number
  }))
  default = {}
}

variable "custom_domain_name" {
  description = "Public domain name for the Kafka bootstrap endpoint (via App Gateway)."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID. Used to derive the OAuth token endpoint URL by convention."
  type        = string
}

variable "schema_registry_url" {
  description = "Apicurio/Confluent-compatible Schema Registry base URL (e.g. https://eventhub.example.com)."
  type        = string
  default     = null
}

variable "sr_scope" {
  description = "OAuth scope for the Schema Registry (api://<apicurio-client-id>/.default)."
  type        = string
  default     = null
}

variable "consumer_group_id" {
  description = "Kafka consumer group ID written into client.properties."
  type        = string
  default     = "default-consumer-group"
}

variable "key_vault_id" {
  description = "Key Vault resource ID where client config secrets are stored."
  type        = string
}

variable "appgw_subnet_id" {
  description = "Subnet ID for the Application Gateway."
  type        = string
}

variable "appgw_identity_id" {
  description = "User-assigned managed identity ID for Key Vault certificate access."
  type        = string
}

variable "kv_cert_secret_id" {
  description = "Key Vault secret ID of the TLS certificate."
  type        = string
}

variable "apicurio_fqdn" {
  description = "FQDN of the Apicurio container group. If null, a dummy value is used for App Gateway."
  type        = string
  default     = "apicurio.local"
}

