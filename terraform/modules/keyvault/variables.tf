variable "name" {
  description = "Name of the Key Vault (must be globally unique, max 24 chars)."
  type        = string
  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 24 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name))
    error_message = "Key Vault name must be 3-24 chars, start with a letter, and contain only alphanumerics or hyphens."
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

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "deployer_object_id" {
  description = "Object ID of the deploying principal (gets Secrets Officer + Certificates Officer)."
  type        = string
}

variable "appgw_principal_id" {
  description = "Principal ID of the App Gateway managed identity (gets Secrets User)."
  type        = string
  default     = null
}

variable "pfx_base64" {
  description = "Base64-encoded PFX certificate to store."
  type        = string
  sensitive   = true
  default     = null
}

variable "pfx_password" {
  description = "Password for the PFX certificate."
  type        = string
  sensitive   = true
  default     = null
}

variable "sku_name" {
  description = "SKU of the Key Vault (standard or premium)."
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be 'standard' or 'premium'."
  }
}
