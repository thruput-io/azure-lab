# Integration test for the kafka/schema-registry submodule.
# Verifies GET/POST of schemas using the Confluent-compatible endpoint (/apis/ccompat/v7).
#
# What this test proves:
#   - Apicurio container deploys and becomes healthy
#   - POST a JSON schema with subject name following Confluent naming standards
#     (<topic>-value, e.g. internal.test.test-event.event.v1-value)
#   - GET the schema back and verify it matches
#   - DELETE the subject (cleanup)
#
# Prerequisites:
#   - Azure credentials with permission to create container groups
#   - curl available on the test runner
#
# Run from submodule root:
#   cd terraform/modules/kafka/schema-registry
#   terraform test -filter=tests/integration.tftest.hcl

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "random" {}

provider "null" {}

# --- Run 1: deploy Apicurio ---
run "setup" {
  command = apply

  module {
    source = "./tests/setup_sr"
  }
}

run "deploy_schema_registry" {
  command = apply

  variables {
    location            = "East US"
    resource_group_name = run.setup.resource_group_name
    dns_name_label      = run.setup.dns_label
    acr_login_server    = run.setup.acr_login_server
    acr_id              = run.setup.acr_id
    tenant_id           = run.setup.tenant_id
    apicurio_client_id  = run.setup.apicurio_client_id
  }

  assert {
    condition     = output.fqdn != ""
    error_message = "Apicurio FQDN must not be empty"
  }

  assert {
    condition     = endswith(output.ccompat_url, "/apis/ccompat/v7")
    error_message = "ccompat_url must end with /apis/ccompat/v7"
  }
}

# --- Run 2: verify schema GET/POST via Confluent-compatible API ---
run "verify_schema_get_post" {
  command = apply

  module {
    source = "./tests/setup_sr_schema"
  }

  variables {
    ccompat_url = run.deploy_schema_registry.ccompat_url
    subject     = "internal.test.test-event.event.v1-value"
    schema = jsonencode({
      type = "object"
      properties = {
        id      = { type = "string" }
        payload = { type = "string" }
      }
      required = ["id", "payload"]
    })
  }

  assert {
    condition     = output.schema_id > 0
    error_message = "POST schema must return a positive schema ID"
  }

  assert {
    condition     = output.subject_exists == true
    error_message = "GET /subjects must list the posted subject"
  }
}
