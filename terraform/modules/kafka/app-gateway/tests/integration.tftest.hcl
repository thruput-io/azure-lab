# Integration test for the kafka/app-gateway submodule.
# Verifies TLS on port 443 (HTTPS) and port 9093 (Kafka/TLS) against the deployed gateway.
#
# What this test proves:
#   - Application Gateway deploys with correct ports
#   - TLS certificate is valid and trusted on :443
#   - TLS handshake succeeds on :9093 (Kafka listener)
#   - Certificate has at least 7 days remaining
#
# Prerequisites:
#   - Azure credentials with permission to create Application Gateways
#   - openssl available on the test runner
#   - custom_domain_name DNS resolves to the gateway public IP
#
# Run from submodule root:
#   cd terraform/modules/kafka/app-gateway
#   TF_VAR_custom_domain_name=eventhub.example.com \
#   TF_VAR_kv_cert_secret_id=https://... \
#   terraform test -filter=tests/integration.tftest.hcl

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "null" {}

# --- Run 1: verify TLS on :443 ---
run "verify_tls_443" {
  command = apply

  module {
    source = "./tests/setup_tls_check"
  }

  variables {
    domain = var.custom_domain_name
    port   = 443
  }

  assert {
    condition     = output.tls_valid == true
    error_message = "TLS certificate on :443 must be valid and trusted"
  }

  assert {
    condition     = output.days_remaining >= 7
    error_message = "TLS certificate on :443 must have at least 7 days remaining"
  }
}

# --- Run 2: verify TLS handshake on :9093 ---
run "verify_tls_9093" {
  command = apply

  module {
    source = "./tests/setup_tls_check"
  }

  variables {
    domain = var.custom_domain_name
    port   = 9093
  }

  assert {
    condition     = output.tls_valid == true
    error_message = "TLS handshake on :9093 (Kafka) must succeed"
  }
}
