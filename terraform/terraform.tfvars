location                = "East US"
resource_group_name     = "rg-eventhub-appgw-lab"
custom_domain_name      = "eventhub.grayskull.se"
keyvault_name           = "kv-lab-8ae187ea"
eventhub_namespace_name = "evh-lab-8ae187ea"
topics = {
  "orders.placed" = {
    name              = "orders.placed"
    partition_count   = 4
    message_retention = 1
  }
  "checks.kafka" = {
    name              = "checks.kafka"
    partition_count   = 2
    message_retention = 1
  }
}
