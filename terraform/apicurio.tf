resource "azurerm_container_group" "apicurio" {
  name                = "aci-apicurio"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = "apicurio-lab"
  os_type             = "Linux"

  container {
    name   = "postgres"
    image  = "postgres:16-alpine"
    cpu    = "0.5"
    memory = "0.5"

    environment_variables = {
      POSTGRES_DB       = "apicuriodb"
      POSTGRES_USER     = "apicurio"
      POSTGRES_PASSWORD = "password" # PoC only, ephemeral
    }

    ports {
      port     = 5432
      protocol = "TCP"
    }
  }

  container {
    name   = "apicurio-registry"
    image  = "apicurio/apicurio-registry:3.2.2"
    cpu    = 1.0
    memory = "1.5"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      APICURIO_STORAGE_KIND        = "sql"
      APICURIO_STORAGE_SQL_KIND    = "postgresql"
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
