resource "azurerm_container_registry" "acr" {
  name                = "acrlab${replace(azurerm_resource_group.rg.name, \"-\", \"\")}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}
