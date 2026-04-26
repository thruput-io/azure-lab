variable "name" {
  description = "Name of the Application Gateway."
  type        = string
  default     = "appgw-eventhub-lab"
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "appgw_subnet_id" {
  description = "Subnet ID for the Application Gateway."
  type        = string
}

variable "public_ip_domain_label" {
  description = "DNS label for the public IP (becomes <label>.<region>.cloudapp.azure.com)."
  type        = string
  default     = "thruput-gw-lab"
}

variable "identity_id" {
  description = "User-assigned managed identity ID for Key Vault certificate access."
  type        = string
}

variable "kv_cert_secret_id" {
  description = "Key Vault secret ID of the TLS certificate."
  type        = string
}

variable "custom_domain_name" {
  description = "Custom domain name used for TLS listeners (SNI)."
  type        = string
}

variable "eventhub_namespace_fqdn" {
  description = "FQDN of the Event Hub namespace (e.g. evh-xxx.servicebus.windows.net)."
  type        = string
}

variable "apicurio_fqdn" {
  description = "FQDN of the Apicurio container group."
  type        = string
}
