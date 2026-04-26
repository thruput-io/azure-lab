# Unit tests for the kafka/app-gateway submodule.
# Uses mock providers — no real Azure resources are created.
# Run: cd terraform/modules/kafka/app-gateway && terraform test -filter=tests/unit.tftest.hcl

mock_provider "azurerm" {}

variables {
  location                = "East US"
  resource_group_name     = "rg-unit-test"
  appgw_subnet_id         = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-appgw"
  identity_id             = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-appgw"
  kv_cert_secret_id       = "https://kv-test.vault.azure.net/secrets/appgw-custom-cert/abc123"
  custom_domain_name      = "eventhub.example.com"
  eventhub_namespace_fqdn = "evh-test.servicebus.windows.net"
  apicurio_fqdn           = "apicurio-lab.eastus.azurecontainer.io"
}

# --- Test: port 443 frontend port is configured ---
run "port_443_configured" {
  command = plan

  assert {
    condition     = contains([for fp in azurerm_application_gateway.this.frontend_port : fp.port], 443)
    error_message = "Frontend port 443 (HTTPS) must be configured"
  }
}

# --- Test: port 9093 frontend port is configured ---
run "port_9093_configured" {
  command = plan

  assert {
    condition     = contains([for fp in azurerm_application_gateway.this.frontend_port : fp.port], 9093)
    error_message = "Frontend port 9093 (Kafka/TLS) must be configured"
  }
}

# --- Test: port 5671 frontend port is configured ---
run "port_5671_configured" {
  command = plan

  assert {
    condition     = contains([for fp in azurerm_application_gateway.this.frontend_port : fp.port], 5671)
    error_message = "Frontend port 5671 (AMQP/TLS) must be configured"
  }
}

# --- Test: kafka L4 listener is configured ---
run "kafka_listener_configured" {
  command = plan

  assert {
    condition     = length([for l in azurerm_application_gateway.this.listener : l if l.name == "kafka-listener"]) == 1
    error_message = "kafka-listener must be configured on port 9093"
  }
}

# --- Test: Event Hub backend pool uses correct FQDN ---
run "eventhub_backend_pool" {
  command = plan

  assert {
    condition     = contains([for pool in azurerm_application_gateway.this.backend_address_pool : pool.name], "evh-beap")
    error_message = "evh-beap backend address pool must be configured"
  }
}

# --- Test: SSL certificate references Key Vault secret ---
run "ssl_cert_from_keyvault" {
  command = plan

  assert {
    condition     = length([for cert in azurerm_application_gateway.this.ssl_certificate : cert if cert.name == "managed-cert"]) == 1
    error_message = "managed-cert SSL certificate must be configured"
  }
}

# --- Test: Standard_v2 SKU ---
run "sku_standard_v2" {
  command = plan

  assert {
    condition     = azurerm_application_gateway.this.sku[0].tier == "Standard_v2"
    error_message = "Application Gateway SKU tier must be Standard_v2"
  }
}
