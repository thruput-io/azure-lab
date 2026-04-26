resource "azurerm_container_group" "apicurio" {
  name                = "aci-apicurio"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_address_type     = "Public"
  dns_name_label      = var.dns_name_label
  os_type             = "Linux"

  identity {
    type = "SystemAssigned"
  }

  container {
    name   = "apicurio-registry"
    image  = "${var.acr_login_server}/apicurio/apicurio-registry:${var.image_tag}"
    cpu    = 1.0
    memory = "1.5"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      QUARKUS_OIDC_TENANT_ENABLED  = "true"
      QUARKUS_OIDC_AUTH_SERVER_URL = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
      QUARKUS_OIDC_CLIENT_ID       = var.apicurio_client_id
    }
  }

  tags = {
    environment = "poc"
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_group.apicurio.identity[0].principal_id
}
