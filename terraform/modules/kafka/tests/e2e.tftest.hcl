# E2E test for the kafka parent module.
# Verifies that client.properties is the correct artifact
# that can be used as the ONLY input for Kafka clients.
#
# What this test proves:
#   1. client.properties produces + consumes a message via cp-kafka 8.2.0
#      using the file as the only input (no credentials hardcoded in the test)
#   2. Avro produce + consume via cp-schema-registry:8.2.0 (when schema_registry_url is set)
#
# Prerequisites:
#   - Azure credentials with permission to create Event Hub namespaces + Key Vault secrets
#   - Docker available (confluentinc/cp-kafka:8.2.0, confluentinc/cp-schema-registry:8.2.0)
#   - python3 available on the test runner
#
# Run from module root:
#   cd terraform/modules/kafka
#   terraform test -filter=tests/e2e.tftest.hcl
#
# Optional: set TF_VAR_schema_registry_url to enable schema registration + Avro step.

variables {
  schema_registry_url = null
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "random" {}
provider "null" {}
provider "local" {}

# --- Run 1: provision shared test infrastructure ---
run "setup" {
  command = apply
  module {
    source = "./eventhub/tests/setup_evh"
  }
}

# --- Run 2: deploy kafka module (eventhub + KV secrets) ---
run "deploy_kafka" {
  command = apply
  variables {
    location            = "East US"
    resource_group_name = run.setup.resource_group_name
    namespace_name      = run.setup.namespace_name
    pe_subnet_id        = run.setup.pe_subnet_id
    vnet_id             = run.setup.vnet_id
    custom_domain_name  = "eventhub.grayskull.se"
    tenant_id           = run.setup.tenant_id
    schema_registry_url = var.schema_registry_url
    consumer_group_id   = "grayskull-consumer-group"
    key_vault_id        = run.setup.key_vault_id
    topics = {
      e2e = {
        name              = "internal.test.test-event.event.v1"
        partition_count   = 2
        message_retention = 1
      }
    }
  }

  assert {
    condition     = output.client_properties != ""
    error_message = "client.properties KV secret must not be empty"
  }
}

# --- Run 3: e2e round-trip using module outputs as the only input ---
run "e2e_roundtrip" {
  command = apply
  module {
    source = "./tests/setup_e2e"
  }
  variables {
    java_client_properties = run.deploy_kafka.client_properties
    bootstrap_servers      = run.deploy_kafka.bootstrap_servers
    topic_name             = "internal.test.test-event.event.v1"
    schema_registry_url    = var.schema_registry_url
  }

  assert {
    condition     = output.java_consumed_message != ""
    error_message = "client.properties produce+consume round-trip must return a non-empty message"
  }
}
