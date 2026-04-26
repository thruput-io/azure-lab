# Unit tests for the kafka/eventhub submodule.
# Uses mock providers — no real Azure resources are created.
# Run: cd terraform/modules/kafka/eventhub && terraform test -filter=tests/unit.tftest.hcl

mock_provider "azurerm" {}

variables {
  namespace_name      = "evh-unit-test"
  location            = "East US"
  resource_group_name = "rg-unit-test"
  pe_subnet_id        = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
  vnet_id             = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  topics = {
    orders = {
      name              = "orders.placed"
      partition_count   = 4
      message_retention = 1
    }
    checks = {
      name              = "checks.kafka"
      partition_count   = 2
      message_retention = 1
    }
  }
}

# --- Test: default topics are created ---
run "default_topics_created" {
  command = plan

  assert {
    condition     = length(azurerm_eventhub.topics) == 2
    error_message = "Two default topics (orders, checks) must be planned"
  }
}

# --- Test: orders topic has correct name ---
run "orders_topic_name" {
  command = plan

  assert {
    condition     = azurerm_eventhub.topics["orders"].name == "orders.placed"
    error_message = "orders topic name must be 'orders.placed'"
  }
}

# --- Test: checks topic has correct name ---
run "checks_topic_name" {
  command = plan

  assert {
    condition     = azurerm_eventhub.topics["checks"].name == "checks.kafka"
    error_message = "checks topic name must be 'checks.kafka'"
  }
}

# --- Test: namespace uses Premium SKU ---
run "namespace_sku_is_premium" {
  command = plan

  assert {
    condition     = azurerm_eventhub_namespace.this.sku == "Premium"
    error_message = "Event Hub namespace SKU must be Premium (required for OAuth/OAUTHBEARER)"
  }
}

# --- Test: private endpoint is created ---
run "private_endpoint_created" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.evh_pe.name == "pe-evh-unit-test"
    error_message = "Private endpoint name must follow pe-<namespace_name> convention"
  }
}

# --- Test: custom topics override defaults ---
run "custom_topics_override" {
  command = plan

  variables {
    topics = {
      test = {
        name              = "internal.test.test-event.event.v1"
        partition_count   = 2
        message_retention = 1
      }
    }
  }

  assert {
    condition     = length(azurerm_eventhub.topics) == 1
    error_message = "Custom topics variable must override defaults — only 1 topic expected"
  }

  assert {
    condition     = azurerm_eventhub.topics["test"].name == "internal.test.test-event.event.v1"
    error_message = "Custom topic name must match provided value"
  }
}
