# Integration test for the keyvault module.
# Deploys a real Key Vault, verifies outputs, writes + reads a secret, then destroys.
# Requires: Azure credentials with permission to create RGs and Key Vaults.
#
# Run from module root:
#   cd terraform/modules/keyvault
#   terraform test -filter=tests/integration.tftest.hcl

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "random" {}

# --- Run 1: create resource group + generate unique names ---
run "setup" {
  command = apply

  module {
    source = "./tests/setup_rg"
  }
}

# --- Run 2: deploy Key Vault and verify outputs ---
run "deploy_and_verify_outputs" {
  command = apply

  variables {
    name                = run.setup.kv_name
    location            = "East US"
    resource_group_name = run.setup.resource_group_name
    tenant_id           = run.setup.tenant_id
    deployer_object_id  = run.setup.deployer_object_id
  }

  assert {
    condition     = output.name != ""
    error_message = "Key Vault name output must not be empty"
  }

  assert {
    condition     = startswith(output.uri, "https://")
    error_message = "Key Vault URI must start with https://"
  }

  assert {
    condition     = output.id != ""
    error_message = "Key Vault resource ID must not be empty"
  }
}

# --- Run 3: write a secret and read it back ---
run "verify_secret_read_write" {
  command = apply

  module {
    source = "./tests/setup_secret_rw"
  }

  variables {
    key_vault_id = run.deploy_and_verify_outputs.id
    secret_name  = "inttest-rw-check"
    secret_value = "hello-from-terraform-test"
  }

  assert {
    condition     = output.read_value == "hello-from-terraform-test"
    error_message = "Secret read back from Key Vault must match the written value"
  }
}
