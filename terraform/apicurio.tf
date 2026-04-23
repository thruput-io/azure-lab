resource "azurerm_container_group" "apicurio" {
  name                = "aci-apicurio"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  os_type             = "Linux"
  subnet_ids          = [azurerm_subnet.aci_subnet.id]

  container {
    name   = "postgres"
    image  = "mcr.microsoft.com/oss/bitnami/postgresql:16.2.0" # Use MCR mirror
    cpu    = "0.5"
    memory = "0.5"

    environment_variables = {
      POSTGRESQL_DATABASE = "apicuriodb"
      POSTGRESQL_USERNAME = "apicurio"
      POSTGRESQL_PASSWORD = "password" # PoC only, ephemeral
    }

    ports {
      port     = 5432
      protocol = "TCP"
    }
  }

  container {
    name   = "apicurio-registry"
    image  = "apicurio/apicurio-registry-sql:3.0.6.Final" # 3.x SQL variant
    cpu    = "1.0"
    memory = "1.5"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      APICURIO_DATASOURCE_URL      = "jdbc:postgresql://localhost:5432/apicuriodb"
      APICURIO_DATASOURCE_USERNAME = "apicurio"
      APICURIO_DATASOURCE_PASSWORD = "password"
      
      # Entra ID OIDC Configuration
      QUARKUS_OIDC_AUTH_SERVER_URL = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
      QUARKUS_OIDC_CLIENT_ID       = azuread_application.apicurio.client_id
      REGISTRY_AUTH_TOKEN_TYPE     = "id"
      
      # Role Based Authorization
      APICURIO_AUTH_ROLE_BASED_AUTHORIZATION = "true"
      APICURIO_AUTH_ROLE_SOURCE              = "token"
      APICURIO_AUTH_ROLES_PATH               = "roles" # Entra ID roles are in the 'roles' claim
      
      # Confluent Compatibility is enabled by default in 3.x
    }
  }

  tags = {
    environment = "poc"
  }
}
