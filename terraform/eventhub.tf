resource "azurerm_eventhub_namespace" "evh" {
  name                = "evh-lab-${random_id.kvname.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_private_endpoint" "evh_pe" {
  name                = "pe-eventhub"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe_subnet.id

  private_service_connection {
    name                           = "psc-eventhub"
    private_connection_resource_id = azurerm_eventhub_namespace.evh.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }
}

resource "azurerm_private_dns_zone" "evh_dns" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "evh_dns_link" {
  name                  = "link-evh-vnet"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.evh_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "evh_a_record" {
  name                = azurerm_eventhub_namespace.evh.name
  zone_name           = azurerm_private_dns_zone.evh_dns.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.evh_pe.private_service_connection[0].private_ip_address]
}
