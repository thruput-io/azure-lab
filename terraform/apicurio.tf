resource "azurerm_container_group" "apicurio" {
  name                = "aci-apicurio"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = "apicurio-lab"
  os_type             = "Linux"

  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }

  container {
    name   = "apicurio-registry"
    image  = "${azurerm_container_registry.acr.login_server}/apicurio/apicurio-registry:3.2.2"
    cpu    = 1.0
    memory = "1.5"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      QUARKUS_OIDC_TENANT_ENABLED = "false"
      APICURIO_STORAGE_KIND = "mem"


    }
  }

  tags = {
    environment = "poc"
  }

}
