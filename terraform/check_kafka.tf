
check "schema_registry_reachable" {
  data "external" "schema_registry_health" {
    program = ["bash", "-lc", <<-EOT
      set -euo pipefail

      QUERY_JSON=$(cat)
      DOMAIN=$(printf '%s' "$QUERY_JSON" | jq -r '.domain')
      TENANT_ID=$(printf '%s' "$QUERY_JSON" | jq -r '.tenant_id')
      CLIENT_ID=$(printf '%s' "$QUERY_JSON" | jq -r '.client_id')
      CLIENT_SECRET=$(printf '%s' "$QUERY_JSON" | jq -r '.client_secret')
      SCOPE=$(printf '%s' "$QUERY_JSON" | jq -r '.scope')

      TOKEN_ENDPOINT="https://login.microsoftonline.com/$${TENANT_ID}/oauth2/v2.0/token"
      ACCESS_TOKEN=$(curl -sS -X POST "$TOKEN_ENDPOINT" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$${CLIENT_ID}" \
        --data-urlencode "client_secret=$${CLIENT_SECRET}" \
        --data-urlencode "scope=$${SCOPE}" \
        | jq -r '.access_token')

      if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        jq -n --arg status_code "000" '{status_code: $status_code}'
        exit 0
      fi

      HTTP_STATUS=$(curl -sS -o /dev/null -w "%%{http_code}" \
        -H "Authorization: Bearer $${ACCESS_TOKEN}" \
        "https://$${DOMAIN}:8081/subjects")

      jq -n --arg status_code "$HTTP_STATUS" '{status_code: $status_code}'
    EOT
    ]

    query = {
      domain        = var.custom_domain_name
      tenant_id     = data.azurerm_client_config.current.tenant_id
      client_id     = azuread_application.kafka_client.client_id
      client_secret = azuread_application_password.kafka_client_secret.value
      scope         = "https://eventhubs.azure.net/.default"
    }
  }

  assert {
    condition     = tonumber(data.external.schema_registry_health.result.status_code) == 200
    error_message = "Confluent Schema Registry at ${var.custom_domain_name}:8081 is not reachable or returned non-200. Check App Gateway and ACI health."
  }
}
