resource "azurerm_service_plan" "apicurio" {
  name                = "asp-apicurio-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "apicurio" {
  name                = "app-apicurio-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.apicurio.id
  https_only          = false

  site_config {
    application_stack {
      docker_image_name   = "apicurio/apicurio-registry:3.2.2"
      docker_registry_url = "https://index.docker.io"
    }
  }

  app_settings = {
    # In-memory H2 storage — ephemeral, perfect for PoC
    APICURIO_STORAGE_KIND     = "mem"
    WEBSITES_PORT             = "8080"

    # Entra ID OIDC
    QUARKUS_OIDC_AUTH_SERVER_URL = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    QUARKUS_OIDC_CLIENT_ID       = azuread_application.apicurio.client_id
    REGISTRY_AUTH_TOKEN_TYPE     = "id"

    # Role Based Authorization
    APICURIO_AUTH_ROLE_BASED_AUTHORIZATION = "true"
    APICURIO_AUTH_ROLE_SOURCE              = "token"
    APICURIO_AUTH_ROLES_PATH               = "roles"
  }

  tags = {
    environment = "poc"
  }
}
