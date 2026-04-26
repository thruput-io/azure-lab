# Helper module: creates RG and provides ACR + Apicurio app registration details
# for schema-registry integration tests.

variable "location" {
  type    = string
  default = "East US"
}

variable "acr_login_server" {
  type    = string
  default = ""
}

variable "acr_id" {
  type    = string
  default = ""
}

variable "apicurio_client_id" {
  type    = string
  default = ""
}

resource "random_id" "suffix" {
  byte_length = 3
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "test" {
  name     = "rg-sr-inttest-${random_id.suffix.hex}"
  location = var.location
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "dns_label" {
  value = "apicurio-inttest-${random_id.suffix.hex}"
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "acr_login_server" {
  value = var.acr_login_server
}

output "acr_id" {
  value = var.acr_id
}

output "apicurio_client_id" {
  value = var.apicurio_client_id
}
