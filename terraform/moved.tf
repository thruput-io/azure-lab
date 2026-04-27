moved {
  from = azurerm_key_vault.kv
  to   = module.keyvault.azurerm_key_vault.this
}

moved {
  from = azurerm_eventhub_namespace.evh
  to   = module.kafka.module.eventhub.azurerm_eventhub_namespace.this
}

moved {
  from = azurerm_private_endpoint.evh_pe
  to   = module.kafka.module.eventhub.azurerm_private_endpoint.evh_pe
}

moved {
  from = azurerm_private_dns_zone.evh_dns
  to   = module.kafka.module.eventhub.azurerm_private_dns_zone.evh_dns
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.evh_dns_link
  to   = module.kafka.module.eventhub.azurerm_private_dns_zone_virtual_network_link.evh_dns_link
}

moved {
  from = azurerm_private_dns_a_record.evh_a_record
  to   = module.kafka.module.eventhub.azurerm_private_dns_a_record.evh_a_record
}

moved {
  from = azurerm_eventhub.orders_topic
  to   = module.kafka.module.eventhub.azurerm_eventhub.topics["orders.placed"]
}

moved {
  from = azurerm_eventhub.checks_topic
  to   = module.kafka.module.eventhub.azurerm_eventhub.topics["checks.kafka"]
}

moved {
  from = azuread_application.kafka_client
  to   = module.kafka.azuread_application.kafka_client
}

moved {
  from = azuread_service_principal.kafka_client
  to   = module.kafka.azuread_service_principal.kafka_client
}

moved {
  from = azuread_application_password.kafka_client_secret
  to   = module.kafka.azuread_application_password.kafka_client
}

moved {
  from = azurerm_role_assignment.kafka_client_sender
  to   = module.kafka.azurerm_role_assignment.kafka_client_sender
}

moved {
  from = azurerm_role_assignment.kafka_client_receiver
  to   = module.kafka.azurerm_role_assignment.kafka_client_receiver
}

moved {
  from = azurerm_key_vault_secret.kafka_client_secret
  to   = module.kafka.azurerm_key_vault_secret.kafka_client_secret
}