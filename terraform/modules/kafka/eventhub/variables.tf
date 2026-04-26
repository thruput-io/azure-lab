variable "namespace_name" {
  description = "Name of the Event Hub namespace."
  type        = string
  validation {
    condition     = length(var.namespace_name) >= 6 && length(var.namespace_name) <= 50 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.namespace_name))
    error_message = "namespace_name must be 6-50 chars, start with a letter, and contain only alphanumerics or hyphens."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "pe_subnet_id" {
  description = "Subnet ID for the private endpoint."
  type        = string
}

variable "vnet_id" {
  description = "Virtual network ID for the private DNS zone link."
  type        = string
}

variable "topics" {
  description = "Map of Event Hub topics to create. Key = logical name, value = config."
  type = map(object({
    name              = string
    partition_count   = number
    message_retention = number
  }))
  default = {}
}
