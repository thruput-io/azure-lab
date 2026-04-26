# Helper module: produce + consume round-trip via cp-kafka 8.2.0 with OAuth.
# Uses null_resource + local-exec to run Docker commands.
# The properties file is written to /tmp and never committed to git.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }
}

variable "namespace_name" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "connection_string" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "eventhub_scope" {
  type = string
}

locals {
  props_file   = "/tmp/evh-inttest-${var.namespace_name}.properties"
  msg_file     = "/tmp/evh-inttest-${var.namespace_name}-consumed.txt"
  test_message = "{\"check\":\"evh-inttest\",\"topic\":\"${var.topic_name}\"}"
  image        = "confluentinc/cp-kafka:8.2.0"
  java_opts    = "-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
}

# Write OAuth properties file and produce a message
resource "null_resource" "produce" {
  triggers = {
    topic   = var.topic_name
    message = local.test_message
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      cat > "${local.props_file}" <<PROPS
bootstrap.servers=${var.namespace_name}.servicebus.windows.net:9093
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token
sasl.oauthbearer.client.credentials.client.id=${var.client_id}
sasl.oauthbearer.client.credentials.client.secret=${var.client_secret}
sasl.oauthbearer.scope=${var.eventhub_scope}
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;
PROPS
      echo '${local.test_message}' | docker run --rm -i \
        -e JAVA_TOOL_OPTIONS="${local.java_opts}" \
        -v "${local.props_file}:/tmp/client.properties:ro" \
        ${local.image} \
        kafka-json-schema-console-producer \
          --bootstrap-server ${var.namespace_name}.servicebus.windows.net:9093 \
          --producer.config /tmp/client.properties \
          --topic ${var.topic_name} \
          --property value.serializer=org.apache.kafka.common.serialization.StringSerializer
    SHELL
  }
}

# Consume the message back
resource "null_resource" "consume" {
  depends_on = [null_resource.produce]

  triggers = {
    topic = var.topic_name
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      docker run --rm \
        -e JAVA_TOOL_OPTIONS="${local.java_opts}" \
        -v "${local.props_file}:/tmp/client.properties:ro" \
        ${local.image} \
        kafka-json-schema-console-consumer \
          --bootstrap-server ${var.namespace_name}.servicebus.windows.net:9093 \
          --consumer.config /tmp/client.properties \
          --topic ${var.topic_name} \
          --from-beginning \
          --max-messages 1 \
          --timeout-ms 30000 \
          --property value.deserializer=org.apache.kafka.common.serialization.StringDeserializer 2>&1 | grep '^{' | head -1 > "${local.msg_file}"
      cat "${local.msg_file}"
    SHELL
  }
}

data "local_file" "consumed" {
  depends_on = [null_resource.consume]
  filename   = local.msg_file
}

output "consumed_message" {
  description = "The message consumed from the topic — must be non-empty for the test to pass."
  value       = trimspace(data.local_file.consumed.content)
}
