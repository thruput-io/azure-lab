resource "azurerm_public_ip" "appgw_pip" {
  name                = "pip-appgw-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

locals {
  backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.vnet.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.vnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.vnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.vnet.name}-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
  name                = "appgw-eventhub-lab"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  frontend_port {
    name = "port_443"
    port = 443
  }

  frontend_port {
    name = "port_5671"
    port = 5671
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
    fqdns = [format("%s.servicebus.windows.net", azurerm_eventhub_namespace.evh.name)]
  }

  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  backend_setting {
    name                                = "amqp-be-settings"
    port                                = 5671
    protocol                            = "Tls"
    timeout                             = 60
    pick_host_name_from_backend_address = true
  }

  # HTTPS Listener (for REST API)
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_443"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-custom-cert"
    host_name                      = var.custom_domain_name
  }

  # AMQP Listener (for Port 5671 - Layer 4 TLS)
  http_listener {
    name                           = "amqp-listener"
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_5671"
    protocol                       = "Tls"
    ssl_certificate_name           = "appgw-custom-cert"
    host_name                      = var.custom_domain_name
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  request_routing_rule {
    name                       = "amqp-rule"
    priority                   = 110
    rule_type                  = "Basic"
    http_listener_name         = "amqp-listener"
    backend_address_pool_name  = local.backend_address_pool_name
    backend_settings_name      = "amqp-be-settings"
  }

  ssl_certificate {
    name                = "appgw-custom-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.custom_cert.secret_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw_id.id]
  }

  # Wait for RBAC to propagate
  depends_on = [
    azurerm_role_assignment.appgw_kv_reader,
    azurerm_key_vault_certificate.custom_cert
  ]
}
