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
      # In-memory H2 storage — ephemeral, perfect for PoC
      APICURIO_STORAGE_KIND = "mem"

      # Entra ID OIDC
      QUARKUS_OIDC_AUTH_SERVER_URL = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
      QUARKUS_OIDC_CLIENT_ID       = azuread_application.apicurio.client_id
      REGISTRY_AUTH_TOKEN_TYPE     = "id"

      # Role Based Authorization
      APICURIO_AUTH_ROLE_BASED_AUTHORIZATION = "true"
      APICURIO_AUTH_ROLE_SOURCE              = "token"
      APICURIO_AUTH_ROLES_PATH               = "roles"
    }
  }

  tags = {
    environment = "poc"
  }

  depends_on = [null_resource.acr_import_apicurio]
}
