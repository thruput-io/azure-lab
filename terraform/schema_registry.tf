# Event Hub topic naming convention: <domain>.<entity>
resource "azurerm_eventhub" "orders_topic" {
  name              = "orders.placed"
  namespace_id      = azurerm_eventhub_namespace.evh.id
  partition_count   = 4
  message_retention = 1
}

# Dedicated topic for automated Kafka connectivity checks (port 9093)
resource "azurerm_eventhub" "checks_topic" {
  name              = "checks.kafka"
  namespace_id      = azurerm_eventhub_namespace.evh.id
  partition_count   = 2
  message_retention = 1
}

# Schema Group - Avro with Forward compatibility
resource "azurerm_eventhub_namespace_schema_group" "orders_schema_group" {
  name                 = "orders-schema-group"
  namespace_id         = azurerm_eventhub_namespace.evh.id
  schema_compatibility = "Forward"
  schema_type          = "Avro"
}
