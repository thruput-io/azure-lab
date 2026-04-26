# Unit tests for the kafka/schema-registry submodule.
# Uses mock providers — no real Azure resources are created.
# Run: cd terraform/modules/kafka/schema-registry && terraform test -filter=tests/unit.tftest.hcl

mock_provider "azurerm" {}

variables {
  location            = "East US"
  resource_group_name = "rg-unit-test"
  acr_login_server    = "acrlab.azurecr.io"
  acr_id              = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/acrlab"
  tenant_id           = "00000000-0000-0000-0000-000000000001"
  apicurio_client_id  = "00000000-0000-0000-0000-000000000002"
}

# --- Test: container uses correct image tag (default) ---
run "default_image_tag" {
  command = plan

  assert {
    condition     = azurerm_container_group.apicurio.container[0].image == "acrlab.azurecr.io/apicurio/apicurio-registry:3.2.2"
    error_message = "Default image tag must be 3.2.2"
  }
}

# --- Test: custom image tag is applied ---
run "custom_image_tag" {
  command = plan

  variables {
    image_tag = "8.2.0"
  }

  assert {
    condition     = azurerm_container_group.apicurio.container[0].image == "acrlab.azurecr.io/apicurio/apicurio-registry:8.2.0"
    error_message = "Custom image tag must be reflected in container image"
  }
}

# --- Test: OIDC env vars are set correctly ---
run "oidc_env_vars" {
  command = plan

  assert {
    condition     = azurerm_container_group.apicurio.container[0].environment_variables["QUARKUS_OIDC_TENANT_ENABLED"] == "true"
    error_message = "QUARKUS_OIDC_TENANT_ENABLED must be 'true'"
  }

  assert {
    condition     = azurerm_container_group.apicurio.container[0].environment_variables["QUARKUS_OIDC_CLIENT_ID"] == "00000000-0000-0000-0000-000000000002"
    error_message = "QUARKUS_OIDC_CLIENT_ID must match apicurio_client_id variable"
  }
}

# --- Test: port 8080 is exposed ---
run "port_8080_exposed" {
  command = plan

  assert {
    condition     = contains([for p in azurerm_container_group.apicurio.container[0].ports : p.port], 8080)
    error_message = "Container must expose port 8080"
  }
}

# --- Test: dns_name_label is set on the container group ---
# ccompat_url depends on fqdn which is unknown at plan time (mock provider).
# The URL path suffix /apis/ccompat/v7 is verified in the integration test.
run "dns_label_set" {
  command = plan

  assert {
    condition     = azurerm_container_group.apicurio.dns_name_label == "apicurio-lab"
    error_message = "dns_name_label must match the default value 'apicurio-lab'"
  }
}

# --- Test: managed identity is SystemAssigned (no admin credentials) ---
run "managed_identity_system_assigned" {
  command = plan

  assert {
    condition     = azurerm_container_group.apicurio.identity[0].type == "SystemAssigned"
    error_message = "Container group must use SystemAssigned managed identity — no ACR admin credentials allowed"
  }
}
