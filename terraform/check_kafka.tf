
check "schema_registry_reachable" {
  data "http" "schema_registry_health" {
    url = "https://${var.custom_domain_name}/subjects"
    request_headers = {
      Authorization = "Basic ${base64encode("${azuread_application.kafka_client.client_id}:${azuread_application_password.kafka_client_secret.value}")}"
    }
  }

  assert {
    condition     = data.http.schema_registry_health.status_code == 200
    error_message = "Schema Registry endpoint at ${var.custom_domain_name} is not reachable or returned non-200. Check DNS, App Gateway, and RBAC."
  }
}
