# Unit tests for the keyvault module.
# Uses mock providers — no real Azure resources are created.
# Run: terraform test -filter=tests/unit.tftest.hcl

mock_provider "azurerm" {}

variables {
  name                = "kv-unit-test"
  location            = "East US"
  resource_group_name = "rg-unit-test"
  tenant_id           = "00000000-0000-0000-0000-000000000001"
  deployer_object_id  = "00000000-0000-0000-0000-000000000002"
}

# --- Test: basic outputs are populated ---
run "outputs_are_populated" {
  command = plan

  assert {
    condition     = output.name == "kv-unit-test"
    error_message = "output.name must equal the input var.name"
  }
}

# --- Test: no cert resources when pfx vars are null ---
run "no_cert_when_pfx_null" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault_certificate.cert) == 0
    error_message = "cert resource must not be created when pfx_base64/pfx_password are null"
  }
}

# --- Test: cert resource created when pfx vars are provided ---
run "cert_created_when_pfx_provided" {
  command = plan

  variables {
    pfx_base64   = "dGVzdA=="
    pfx_password = "secret"
  }

  assert {
    condition     = length(azurerm_key_vault_certificate.cert) == 1
    error_message = "cert resource must be created when pfx_base64 and pfx_password are set"
  }
}

# --- Test: appgw role assignment created only when principal provided ---
run "appgw_role_created_when_principal_provided" {
  command = plan

  variables {
    appgw_principal_id = "00000000-0000-0000-0000-000000000003"
  }

  assert {
    condition     = length(azurerm_role_assignment.appgw_secrets_user) == 1
    error_message = "appgw_secrets_user role assignment must be created when appgw_principal_id is set"
  }
}

# --- Test: appgw role assignment absent when no principal ---
run "appgw_role_absent_when_no_principal" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.appgw_secrets_user) == 0
    error_message = "appgw_secrets_user role assignment must not be created when appgw_principal_id is null"
  }
}
