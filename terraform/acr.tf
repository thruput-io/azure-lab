resource "azurerm_container_registry" "acr" {
  name                = "acrlab${replace(azurerm_resource_group.rg.name, "-", "")}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Import Apicurio image from Docker Hub into ACR after ACR is created
resource "null_resource" "acr_import_apicurio" {
  triggers = {
    acr_id = azurerm_container_registry.acr.id
    image  = "apicurio/apicurio-registry:3.2.2"
  }

  provisioner "local-exec" {
    command = "az acr import --name ${azurerm_container_registry.acr.name} --source docker.io/apicurio/apicurio-registry:3.2.2 --image apicurio/apicurio-registry:3.2.2 --force"
  }

  depends_on = [azurerm_container_registry.acr]
}
