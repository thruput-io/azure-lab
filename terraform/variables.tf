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
