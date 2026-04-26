# Unit tests for the kafka parent module.
# Verifies that the module wires client-config correctly and exposes all required outputs.
# Formatting assertions live in client-config/tests/unit.tftest.hcl.
# Uses mock providers — no real Azure resources are created.
#
# Run: cd terraform/modules/kafka && terraform test -filter=tests/unit.tftest.hcl

mock_provider "azurerm" {
  mock_resource "azurerm_eventhub_namespace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-unit-test/providers/Microsoft.EventHub/namespaces/evh-unit-test"
    }
  }
  mock_resource "azurerm_role_assignment" {
    defaults = {}
  }
  mock_resource "azurerm_key_vault_secret" {
    defaults = {}
  }
}
mock_provider "azuread" {
  mock_resource "azuread_application" {
    defaults = {
      id        = "/applications/00000000-0000-0000-0000-000000000010"
      client_id = "c9903fe3-a886-4e0e-b59f-bf52242facb3"
    }
  }
  mock_resource "azuread_application_password" {
    defaults = {
      value = "mock-client-secret"
    }
  }
  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000099"
    }
  }
  mock_resource "azuread_application_identifier_uri" {
    defaults = {}
  }
}

variables {
  location            = "East US"
  resource_group_name = "rg-unit-test"
  namespace_name      = "evh-unit-test"
  pe_subnet_id        = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
  vnet_id             = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  custom_domain_name  = "eventhub.example.com"
  tenant_id           = "00000000-0000-0000-0000-000000000001"
  schema_registry_url = "https://eventhub.example.com"
  sr_scope            = "api://apicurio-client-id/.default"
  consumer_group_id   = "grayskull-consumer-group"
  key_vault_id        = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv-test"
  topics = {
    orders = {
      name              = "orders.placed"
      partition_count   = 2
      message_retention = 1
    }
  }
}

# ============================================================
# client.properties output — single unified Confluent .properties file
# ============================================================

run "client_props_has_bootstrap_servers" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "bootstrap.servers=eventhub.example.com:9093")
    error_message = "client.properties must contain 'bootstrap.servers='"
  }
}

run "client_props_has_security_protocol" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "security.protocol=SASL_SSL")
    error_message = "client.properties must contain 'security.protocol=SASL_SSL'"
  }
}

run "client_props_has_sasl_mechanism" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.mechanism=OAUTHBEARER")
    error_message = "client.properties must contain 'sasl.mechanism=OAUTHBEARER'"
  }
}

run "client_props_has_oauthbearer_method" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.method=oidc")
    error_message = "client.properties must contain 'sasl.oauthbearer.method=oidc'"
  }
}

run "client_props_has_client_id" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.client.id=")
    error_message = "client.properties must contain 'sasl.oauthbearer.client.id='"
  }
}

run "client_props_has_client_secret" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.client.secret=")
    error_message = "client.properties must contain 'sasl.oauthbearer.client.secret='"
  }
}

run "client_props_has_scope" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.scope=")
    error_message = "client.properties must contain 'sasl.oauthbearer.scope='"
  }
}

run "client_props_has_token_endpoint" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.token.endpoint.url=")
    error_message = "client.properties must contain 'sasl.oauthbearer.token.endpoint.url='"
  }
}

run "client_props_has_sr_url" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "schema.registry.url=")
    error_message = "client.properties must contain 'schema.registry.url=' when schema_registry_url is set"
  }
}

run "client_props_has_json_schema_serializer" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "value.serializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer")
    error_message = "client.properties must contain KafkaJsonSchemaSerializer"
  }
}

run "client_props_has_json_schema_deserializer" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "value.deserializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializer")
    error_message = "client.properties must contain KafkaJsonSchemaDeserializer"
  }
}

run "client_props_has_group_id" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "group.id=grayskull-consumer-group")
    error_message = "client.properties must contain 'group.id='"
  }
}

run "client_props_has_auto_offset_reset" {
  command = apply
  assert {
    condition     = strcontains(output.client_properties, "auto.offset.reset=earliest")
    error_message = "client.properties must contain 'auto.offset.reset=earliest'"
  }
}
