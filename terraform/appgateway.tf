resource "azurerm_public_ip" "appgw_pip" {
  name                = "pip-appgw-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "thruput-gw-lab"
}

locals {
  backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-beap"
  frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.vnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.vnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-rqrt"
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw_id.id]
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

  frontend_port {
    name = "port_9093"
    port = 9093
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name  = local.backend_address_pool_name
    fqdns = [format("%s.servicebus.windows.net", azurerm_eventhub_namespace.evh.name)]
  }

  # L7 Settings (HTTPS)
  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  # L4 Backend (TCP/TLS Proxy)
  backend {
    name               = "amqp-be-settings"
    port               = 5671
    protocol           = "Tls"
    timeout_in_seconds = 60
    host_name          = format("%s.servicebus.windows.net", azurerm_eventhub_namespace.evh.name)
  }

  backend {
    name               = "kafka-be-settings"
    port               = 9093
    protocol           = "Tls"
    timeout_in_seconds = 60
    host_name          = format("%s.servicebus.windows.net", azurerm_eventhub_namespace.evh.name)
  }

  ssl_certificate {
    name                = "managed-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.custom_cert.secret_id
  }

  # L7 Listener (HTTPS)
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_443"
    protocol                       = "Https"
    ssl_certificate_name           = "managed-cert"
    host_name                      = var.custom_domain_name
  }

  # L4 Listener (TCP/TLS)
  listener {
    name                           = "amqp-listener"
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_5671"
    protocol                       = "Tls"
    ssl_certificate_name           = "managed-cert"
    host_names                     = [var.custom_domain_name]
  }

  listener {
    name                           = "kafka-listener"
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_9093"
    protocol                       = "Tls"
    ssl_certificate_name           = "managed-cert"
    host_names                     = [var.custom_domain_name]
  }

  # L7 Rule
  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  # L4 Rule
  routing_rule {
    name                      = "amqp-rule"
    priority                  = 110
    listener_name             = "amqp-listener"
    backend_address_pool_name = local.backend_address_pool_name
    backend_name              = "amqp-be-settings"
  }

  routing_rule {
    name                      = "kafka-rule"
    priority                  = 120
    listener_name             = "kafka-listener"
    backend_address_pool_name = local.backend_address_pool_name
    backend_name              = "kafka-be-settings"
  }

  depends_on = [
    azurerm_role_assignment.appgw_kv_reader,
    azurerm_key_vault_certificate.custom_cert
  ]
}
