resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-lab"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "pe_subnet" {
  name                                           = "snet-pe"
  resource_group_name                            = azurerm_resource_group.rg.name
  virtual_network_name                           = azurerm_virtual_network.vnet.name
  address_prefixes                               = ["10.0.2.0/24"]
}

data "azurerm_client_config" "current" {}

module "keyvault" {
  source              = "./modules/keyvault"
  name                = var.keyvault_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  deployer_object_id  = data.azurerm_client_config.current.object_id
}

module "kafka" {
  source              = "./modules/kafka"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  namespace_name      = var.eventhub_namespace_name
  pe_subnet_id        = azurerm_subnet.pe_subnet.id
  vnet_id             = azurerm_virtual_network.vnet.id
  topics              = var.topics
  custom_domain_name  = var.custom_domain_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  schema_registry_url = "https://${var.custom_domain_name}"
  sr_scope            = "api://${azuread_application.apicurio.client_id}/.default"
  key_vault_id        = module.keyvault.id
}

