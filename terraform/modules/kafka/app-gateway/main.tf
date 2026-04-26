resource "azurerm_public_ip" "appgw_pip" {
  name                = "pip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.public_ip_domain_label
}

locals {
  frontend_ip_configuration_name = "${var.name}-feip"
  listener_name                  = "${var.name}-httplstn"
  request_routing_rule_name      = "${var.name}-rqrt"
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = var.appgw_subnet_id
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
    name  = "evh-beap"
    fqdns = [var.eventhub_namespace_fqdn]
  }

  backend_address_pool {
    name  = "apicurio-beap"
    fqdns = [var.apicurio_fqdn]
  }

  # L7 Settings (HTTP to Apicurio ACI :8080)
  backend_http_settings {
    name                                = "apicurio-be-htst"
    cookie_based_affinity               = "Disabled"
    port                                = 8080
    protocol                            = "Http"
    request_timeout                     = 60
    pick_host_name_from_backend_address = false
    probe_name                          = "apicurio-probe"
  }

  probe {
    name                                      = "apicurio-probe"
    protocol                                  = "Http"
    path                                      = "/apis/ccompat/v7/subjects"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    host                                      = var.apicurio_fqdn
    match {
      status_code = ["200-401"]
    }
  }

  # L4 Backend (TCP/TLS Proxy)
  backend {
    name               = "amqp-be-settings"
    port               = 5671
    protocol           = "Tls"
    timeout_in_seconds = 60
    host_name          = var.eventhub_namespace_fqdn
  }

  backend {
    name               = "kafka-be-settings"
    port               = 9093
    protocol           = "Tls"
    timeout_in_seconds = 60
    host_name          = var.eventhub_namespace_fqdn
  }

  ssl_certificate {
    name                = "managed-cert"
    key_vault_secret_id = var.kv_cert_secret_id
  }

  # L7 Listener (HTTPS :443)
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "port_443"
    protocol                       = "Https"
    ssl_certificate_name           = "managed-cert"
    host_name                      = var.custom_domain_name
  }

  # L4 Listeners (TCP/TLS)
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
    backend_address_pool_name  = "apicurio-beap"
    backend_http_settings_name = "apicurio-be-htst"
  }

  # L4 Rules
  routing_rule {
    name                      = "amqp-rule"
    priority                  = 110
    listener_name             = "amqp-listener"
    backend_address_pool_name = "evh-beap"
    backend_name              = "amqp-be-settings"
  }

  routing_rule {
    name                      = "kafka-rule"
    priority                  = 120
    listener_name             = "kafka-listener"
    backend_address_pool_name = "evh-beap"
    backend_name              = "kafka-be-settings"
  }
}
