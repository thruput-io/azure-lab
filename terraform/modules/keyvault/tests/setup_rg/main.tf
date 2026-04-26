# Helper module: creates a resource group + random suffix for integration tests.

variable "location" {
  type    = string
  default = "East US"
}

resource "random_id" "suffix" {
  byte_length = 3
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "test" {
  name     = "rg-kv-inttest-${random_id.suffix.hex}"
  location = var.location
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "kv_name" {
  value = "kv-inttest-${random_id.suffix.hex}"
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "deployer_object_id" {
  value = data.azurerm_client_config.current.object_id
}
