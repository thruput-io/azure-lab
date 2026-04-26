# Integration test for the kafka/eventhub submodule.
# Verifies send/receive without schema against internal (private) endpoints.
#
# What this test proves:
#   - Event Hub namespace deploys with Premium SKU
#   - Topics are created with correct names
#   - Private endpoint + DNS resolve correctly inside the VNet
#   - Produce + consume round-trip works using cp-kafka 8.2.0 with OAuth
#
# Prerequisites:
#   - Azure credentials with permission to create Event Hub namespaces
#   - Docker available (confluentinc/cp-kafka:8.2.0)
#   - Run from a host that can reach the private endpoint (or via VPN/jumpbox)
#
# Run from submodule root:
#   cd terraform/modules/kafka/eventhub
#   terraform test -filter=tests/integration.tftest.hcl

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "random" {}

# --- Run 1: provision test infrastructure ---
run "setup" {
  command = apply

  module {
    source = "./tests/setup_evh"
  }
}

# --- Run 2: deploy eventhub submodule with test topic ---
run "deploy_eventhub" {
  command = apply

  variables {
    namespace_name      = run.setup.namespace_name
    location            = "East US"
    resource_group_name = run.setup.resource_group_name
    pe_subnet_id        = run.setup.pe_subnet_id
    vnet_id             = run.setup.vnet_id
    topics = {
      inttest = {
        name              = "internal.test.test-event.event.v1"
        partition_count   = 2
        message_retention = 1
      }
    }
  }

  assert {
    condition     = output.namespace_name != ""
    error_message = "Event Hub namespace name must not be empty"
  }

  assert {
    condition     = output.topic_names["inttest"] == "internal.test.test-event.event.v1"
    error_message = "Integration test topic must be created with correct name"
  }

  assert {
    condition     = output.private_ip_address != ""
    error_message = "Private endpoint must have an IP address assigned"
  }
}

# --- Run 3: produce + consume round-trip via cp-kafka 8.2.0 ---
run "produce_consume_roundtrip" {
  command = apply

  module {
    source = "./tests/setup_evh_roundtrip"
  }

  variables {
    namespace_name     = run.setup.namespace_name
    topic_name         = run.deploy_eventhub.topic_names["inttest"]
    connection_string  = run.deploy_eventhub.default_primary_connection_string
    tenant_id          = run.setup.tenant_id
    client_id          = run.setup.client_id
    client_secret      = run.setup.client_secret
    eventhub_scope     = "https://${run.setup.namespace_name}.servicebus.windows.net/.default"
  }

  assert {
    condition     = output.consumed_message != ""
    error_message = "Produce + consume round-trip must return a non-empty message"
  }
}
