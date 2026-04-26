# Helper module: e2e round-trip using kafka module outputs as the only input.
#
# Verifies plan items 3:
#   3.  Send/receive JSON Schema message using cp-kafka:8.2.0 with client.properties
#       (Confluent unified format — SR URL and OAuth settings inside the file)
#
# Only inputs: java_client_properties, bootstrap_servers from kafka module outputs.
# No credentials are hardcoded — all values come from the module output variables.
# No extraction or conversion of config data at call site — all formatting is in client-config/main.tf.
#
# Prerequisites:
#   - Docker available (confluentinc/cp-kafka:8.2.0)
#
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
}

variable "java_client_properties" {
  description = "Content of client.properties from kafka module KV secret output."
  type        = string
  sensitive   = true
}

variable "bootstrap_servers" {
  description = "Kafka bootstrap servers string (host:port). Passed directly from kafka module output — never extracted from client files."
  type        = string
}

variable "topic_name" {
  description = "Topic to produce/consume against."
  type        = string
}

variable "schema_registry_url" {
  description = "Optional Apicurio/Confluent-compatible Schema Registry base URL (e.g. http://host:8080). If null, schema step is skipped."
  type        = string
  default     = null
}

locals {
  client_props_file = "/tmp/kafka-e2e-client.properties"
  java_msg_file     = "/tmp/kafka-e2e-java-consumed.txt"
  test_message      = "{\"check\":\"kafka-e2e\",\"topic\":\"${var.topic_name}\"}"
  image             = "confluentinc/cp-kafka:8.2.0"
}

# Write client.properties from module output (only input — no credentials hardcoded)
resource "local_file" "client_props" {
  content         = var.java_client_properties
  filename        = local.client_props_file
  file_permission = "0600"
}

# Register a JSON schema via Schema Registry REST API (Confluent-compatible /apis/ccompat/v7)
# Subject name follows Confluent naming: <topic>-value
resource "null_resource" "register_schema" {
  count = var.schema_registry_url != null ? 1 : 0
  triggers = {
    subject = "${var.topic_name}-value"
    url     = var.schema_registry_url
  }
  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      SUBJECT="${var.topic_name}-value"
      SR_URL="${var.schema_registry_url}/apis/ccompat/v7"
      SCHEMA='{"schema":"{\"type\":\"object\",\"properties\":{\"check\":{\"type\":\"string\"},\"topic\":{\"type\":\"string\"}},\"required\":[\"check\",\"topic\"]}","schemaType":"JSON"}'
      echo "Registering schema for subject: $SUBJECT"
      RESPONSE=$(curl -sf -X POST \
        -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
        -d "$SCHEMA" \
        "$SR_URL/subjects/$SUBJECT/versions")
      echo "Register response: $RESPONSE"
      echo "Verifying schema retrieval..."
      curl -sf "$SR_URL/subjects/$SUBJECT/versions/latest" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'schema' in d, 'schema key missing from response'
assert 'id' in d, 'id key missing from response'
print(f\"PASS: schema registered with id={d['id']} for subject={d.get('subject')}\")"
    SHELL
  }
}

# Produce a message using client.properties as the only input
resource "null_resource" "java_produce" {
  depends_on = [local_file.client_props, null_resource.register_schema]
  triggers = {
    topic   = var.topic_name
    message = local.test_message
  }
  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      echo '${local.test_message}' | docker run --rm -i \
        -v "${local.client_props_file}:/tmp/client.properties:ro" \
        ${local.image} \
        kafka-json-schema-console-producer \
          --bootstrap-server ${var.bootstrap_servers} \
          --producer.config /tmp/client.properties \
          --topic ${var.topic_name} \
          --property value.schema='{"type":"object","properties":{"check":{"type":"string"},"topic":{"type":"string"}},"required":["check","topic"]}'
    SHELL
  }
}

# Consume the message back using client.properties as the only input
resource "null_resource" "java_consume" {
  depends_on = [null_resource.java_produce]
  triggers = {
    topic = var.topic_name
  }
  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      docker run --rm \
        -v "${local.client_props_file}:/tmp/client.properties:ro" \
        ${local.image} \
        kafka-json-schema-console-consumer \
          --bootstrap-server ${var.bootstrap_servers} \
          --consumer.config /tmp/client.properties \
          --topic ${var.topic_name} \
          --from-beginning \
          --max-messages 1 \
          --timeout-ms 30000 2>&1 | grep '^{' | head -1 > "${local.java_msg_file}"
      cat "${local.java_msg_file}"
    SHELL
  }
}

data "local_file" "java_consumed" {
  depends_on = [null_resource.java_consume]
  filename   = local.java_msg_file
}

output "java_consumed_message" {
  description = "Message consumed from Kafka via client.properties."
  value       = data.local_file.java_consumed.content
}
