resource "azurerm_eventhub_namespace" "this" {
  name                          = var.namespace_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium"
  capacity                      = 1
  public_network_access_enabled = false
}

locals {
  test_topic_name = "internal.test.test-event.event.v1"
}

# Hardcoded test topic — always present, used by all tests at all levels.
resource "azurerm_eventhub" "test_topic" {
  name              = local.test_topic_name
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = 2
  message_retention = 1
}

resource "azurerm_eventhub" "topics" {
  for_each          = var.topics
  name              = each.value.name
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention
}

resource "azurerm_private_endpoint" "evh_pe" {
  name                = "pe-${var.namespace_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-${var.namespace_name}"
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }
}

resource "azurerm_private_dns_zone" "evh_dns" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "evh_dns_link" {
  name                  = "link-${var.namespace_name}-vnet"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.evh_dns.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_private_dns_a_record" "evh_a_record" {
  name                = azurerm_eventhub_namespace.this.name
  zone_name           = azurerm_private_dns_zone.evh_dns.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.evh_pe.private_service_connection[0].private_ip_address]
}
