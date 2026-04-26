# Unit tests for the client-config formatting module.
# No providers required — pure data transformation, no Azure resources.
#
# One output:
#   client_properties  — single unified Confluent .properties file
#
# Run: cd terraform/modules/kafka/client-config && terraform test -filter=tests/unit.tftest.hcl

variables {
  bootstrap_servers   = "eventhub.example.com:9093"
  client_id           = "c9903fe3-a886-4e0e-b59f-bf52242facb3"
  client_secret       = "mock-client-secret"
  eventhub_scope      = "https://evh-unit-test.servicebus.windows.net/.default"
  token_endpoint_url  = "https://login.microsoftonline.com/00000000-0000-0000-0000-000000000001/oauth2/v2.0/token"
  schema_registry_url = "https://eventhub.example.com"
  consumer_group_id   = "grayskull-consumer-group"
}

# ============================================================
# client.properties — single unified Confluent .properties file
# ============================================================

run "client_props_has_bootstrap_servers" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "bootstrap.servers=eventhub.example.com:9093")
    error_message = "client.properties must contain 'bootstrap.servers='"
  }
}

run "client_props_has_security_protocol" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "security.protocol=SASL_SSL")
    error_message = "client.properties must contain 'security.protocol=SASL_SSL'"
  }
}

run "client_props_has_sasl_mechanism" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.mechanism=OAUTHBEARER")
    error_message = "client.properties must contain 'sasl.mechanism=OAUTHBEARER'"
  }
}

run "client_props_has_oauthbearer_method" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.method=oidc")
    error_message = "client.properties must contain 'sasl.oauthbearer.method=oidc'"
  }
}

run "client_props_has_client_id" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.client.id=")
    error_message = "client.properties must contain 'sasl.oauthbearer.client.id='"
  }
}

run "client_props_has_client_secret" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.client.secret=")
    error_message = "client.properties must contain 'sasl.oauthbearer.client.secret='"
  }
}

run "client_props_has_scope" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.scope=")
    error_message = "client.properties must contain 'sasl.oauthbearer.scope='"
  }
}

run "client_props_has_token_endpoint" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "sasl.oauthbearer.token.endpoint.url=")
    error_message = "client.properties must contain 'sasl.oauthbearer.token.endpoint.url='"
  }
}

run "client_props_has_sr_url" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "schema.registry.url=")
    error_message = "client.properties must contain 'schema.registry.url=' when schema_registry_url is set"
  }
}

run "client_props_has_json_schema_serializer" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "value.serializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer")
    error_message = "client.properties must contain KafkaJsonSchemaSerializer"
  }
}

run "client_props_has_json_schema_deserializer" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "value.deserializer=io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializer")
    error_message = "client.properties must contain KafkaJsonSchemaDeserializer"
  }
}

run "client_props_has_group_id" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "group.id=grayskull-consumer-group")
    error_message = "client.properties must contain 'group.id='"
  }
}

run "client_props_has_auto_offset_reset" {
  command = plan
  assert {
    condition     = strcontains(output.client_properties, "auto.offset.reset=earliest")
    error_message = "client.properties must contain 'auto.offset.reset=earliest'"
  }
}
