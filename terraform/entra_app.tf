# --- Apicurio App Registration ---
resource "azuread_application" "apicurio" {
  display_name = "app-apicurio-registry"

  lifecycle {
    ignore_changes = [identifier_uris]
  }

  app_role {
    allowed_member_types = ["Application", "User"]
    description          = "Full administrative access to the registry."
    display_name         = "sr-admin"
    enabled              = true
    id                   = "49666f21-169b-4408-8924-f58479e0802c"
    value                = "sr-admin"
  }

  app_role {
    allowed_member_types = ["Application", "User"]
    description          = "Read-only access to the registry."
    display_name         = "sr-readonly"
    enabled              = true
    id                   = "f310f3c5-849c-47a3-b40e-6f8e77a16f0d"
    value                = "sr-readonly"
  }

  api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access the registry."
      admin_consent_display_name = "Access Registry"
      enabled                    = true
      id                         = "1e0c40e5-7b56-4c92-95f0-621e25e1a3c7"
      type                       = "User"
      user_consent_description   = "Allow the application to access the registry on your behalf."
      user_consent_display_name  = "Access Registry"
      value                      = "Registry.Access"
    }
  }
}

resource "azuread_application_identifier_uri" "apicurio" {
  application_id = azuread_application.apicurio.id
  identifier_uri = "api://${azuread_application.apicurio.client_id}"
}

resource "azuread_service_principal" "apicurio" {
  client_id = azuread_application.apicurio.client_id
}

# --- Assign sr-admin role to the Kafka client (so it can register schemas) ---
# The kafka module owns the kafka client identity; we reference its output here.
resource "azuread_app_role_assignment" "kafka_client_apicurio_admin" {
  app_role_id         = { for r in azuread_application.apicurio.app_role : r.display_name => r.id }["sr-admin"]
  principal_object_id = module.kafka.kafka_client_principal_id
  resource_object_id  = azuread_service_principal.apicurio.object_id
}

# --- Outputs ---
output "kafka_bootstrap_server" {
  value = "${var.custom_domain_name}:9093"
}

output "schema_registry_endpoint" {
  value = "https://${var.custom_domain_name}"
}

output "topic_names" {
  value = module.kafka.topic_names
}
