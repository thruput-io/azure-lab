variable "location" {
  description = "The Azure Region in which all resources should be created."
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  default     = "rg-eventhub-appgw-lab"
}

variable "custom_domain_name" {
  description = "The custom domain name for the Application Gateway (e.g., eventhub.example.com)."
  type        = string
}

variable "pfx_base64" {
  description = "Base64 encoded PFX certificate."
  type        = string
  sensitive   = true
}

variable "pfx_password" {
  description = "Password for the PFX certificate."
  type        = string
  sensitive   = true
}

variable "keyvault_name" {
  description = "Name of the Key Vault."
  type        = string
  default     = "kv-lab-8ae187ea"
}

variable "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace."
  type        = string
  default     = "evh-lab-8ae187ea"
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
