# ============================================================
# Confluent Schema Registry — self-hosted on Azure Container Instance
# Exposes the standard Confluent /subjects REST API on port 8081.
# Deployed in the VNet so it can reach the Event Hub private endpoint.
# The App Gateway proxies HTTPS :8081 -> ACI :8081 (HTTP within VNet).
# Image is hosted in Azure Container Registry (ACR) to avoid Docker Hub
# rate limits on ACI. The deploy pipeline pushes the image to ACR first.
# ============================================================

# Azure Container Registry for hosting the Confluent SR image
resource "azurerm_container_registry" "acr" {
  name                = "acrconfluentsr${random_id.kvname.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Grant the deployer identity AcrPush to push the image during pipeline
resource "azurerm_role_assignment" "deployer_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

# Dedicated subnet for the Confluent SR ACI
resource "azurerm_subnet" "sr_subnet" {
  name                 = "snet-sr"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "aci-delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Confluent Schema Registry container instance
# Connects to EH Kafka via private endpoint (Private DNS resolves
# evh-lab-xxx.servicebus.windows.net to private IP within VNet).
# Uses SAS $ConnectionString auth (SASL PLAIN) for SR's internal
# Kafka store — this is separate from the client OAUTHBEARER config.
resource "azurerm_container_group" "confluent_sr" {
  name                = "aci-confluent-sr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.sr_subnet.id]
  os_type             = "Linux"
  restart_policy      = "Always"

  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }

  container {
    name   = "confluent-sr"
    image  = "${azurerm_container_registry.acr.login_server}/cp-schema-registry:7.6.0"
    cpu    = "0.5"
    memory = "1"

    ports {
      port     = 8081
      protocol = "TCP"
    }

    environment_variables = {
      SCHEMA_REGISTRY_HOST_NAME                    = "localhost"
      SCHEMA_REGISTRY_LISTENERS                    = "http://0.0.0.0:8081"
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS = "SASL_SSL://${azurerm_eventhub_namespace.evh.name}.servicebus.windows.net:9093"
      SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL = "SASL_SSL"
      SCHEMA_REGISTRY_KAFKASTORE_SASL_MECHANISM    = "PLAIN"
      SCHEMA_REGISTRY_KAFKASTORE_SASL_JAAS_CONFIG  = "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$ConnectionString\" password=\"${azurerm_eventhub_namespace_authorization_rule.confluent_client.primary_connection_string}\";"
      SCHEMA_REGISTRY_KAFKASTORE_TOPIC             = "_schemas"
      SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY_LEVEL   = "FORWARD"
      SCHEMA_REGISTRY_ACCESS_CONTROL_ALLOW_METHODS = "GET,POST,PUT,OPTIONS"
      SCHEMA_REGISTRY_ACCESS_CONTROL_ALLOW_ORIGIN  = "*"
    }
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.evh_dns_link,
    azurerm_private_dns_a_record.evh_a_record
  ]
}

output "confluent_sr_ip" {
  value       = azurerm_container_group.confluent_sr.ip_address
  description = "Private IP of the Confluent Schema Registry ACI (reachable from App Gateway subnet)"
}

output "confluent_sr_url" {
  value       = "https://${var.custom_domain_name}:8081"
  description = "Public Confluent Schema Registry URL via App Gateway"
}
