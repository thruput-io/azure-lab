variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "dns_name_label" {
  description = "DNS label for the container group public IP (becomes <label>.<region>.azurecontainer.io)."
  type        = string
  default     = "apicurio-lab"
}

variable "acr_login_server" {
  description = "ACR login server (e.g. acrlab.azurecr.io)."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the ACR (used to grant AcrPull to the container group managed identity)."
  type        = string
}

variable "image_tag" {
  description = "Apicurio Registry image tag."
  type        = string
  default     = "3.2.2"
}

variable "tenant_id" {
  description = "Azure AD tenant ID for OIDC configuration."
  type        = string
}

variable "apicurio_client_id" {
  description = "Client ID of the Apicurio app registration."
  type        = string
}
