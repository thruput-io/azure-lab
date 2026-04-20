# Azure Event Hub behind Application Gateway (POC)

This Proof of Concept (POC) demonstrates how to expose an **Azure Event Hub** via an **Azure Application Gateway**, utilizing both Layer 7 (HTTPS) and Layer 4 (TLS Proxy) capabilities. This setup allows you to keep your Event Hub namespace private (via Private Link) while providing secure, controlled access through a single entry point with a custom domain.

## Features

- **Private Event Hub**: Event Hub namespace is isolated within a Virtual Network using Private Endpoints.
- **Application Gateway L4/L7 Support**:
    - **HTTPS (Port 443)**: Standard L7 routing for REST API / Schema Registry access.
    - **AMQP over TLS (Port 5671)**: L4 TLS proxying for AMQP clients.
    - **Kafka over TLS (Port 9093)**: L4 TLS proxying for Kafka clients.
- **Key Vault Integration**: Application Gateway uses a User-Assigned Managed Identity to retrieve SSL certificates from Azure Key Vault.
- **Custom Domain**: Configurable custom domain name for all listeners.
- **Entra ID OAuth2**: Kafka clients authenticate via SASL/OAUTHBEARER using an App Registration.
- **Avro Schema Registry**: Schema Registry exposed on port 443 with TopicNameStrategy (default).

## Architecture

```
Internet
   │
   ▼
Application Gateway v2 (public IP, custom domain)
   ├── :443  (L7 HTTPS)  → Event Hub Schema Registry (REST)
   ├── :5671 (L4 TLS)    → Event Hub AMQP
   └── :9093 (L4 TLS)    → Event Hub Kafka
                                │
                         Private Endpoint
                                │
                         Event Hub Namespace
                         (Standard SKU, VNet isolated)
```

Authentication: **SASL/OAUTHBEARER** (Kafka) + **HTTP Basic** (Schema Registry)  
Token issuer: `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token`  
Schema strategy: **TopicNameStrategy** (default) → subject `orders.placed-value`

## Prerequisites

- An Azure Subscription.
- A PFX certificate for your custom domain.
- A custom domain name (you will need to point its DNS to the Application Gateway's Public IP).
- Docker (required on the runner for the smoke test).

## Deployment

### GitHub Actions

This project includes a GitHub Actions pipeline for automated deployment.

#### Prerequisites for CI/CD

1.  **Azure Service Principal**: Create a Service Principal with `Contributor` access and OIDC trust for your GitHub repository.
2.  **GitHub Secrets**: Add the following secrets to your repository:
    - `AZURE_CLIENT_ID`: The application ID of your Service Principal.
    - `AZURE_TENANT_ID`: Your Azure Tenant ID.
    - `AZURE_SUBSCRIPTION_ID`: Your Azure Subscription ID.
    - `PFX_BASE64`: Base64 encoded content of your PFX certificate.
    - `PFX_PASSWORD`: Password for the PFX certificate.
3.  **GitHub Variables**: Add the following variable:
    - `CUSTOM_DOMAIN_NAME`: Your custom domain name (e.g., `eventhub.thruput.se`).

The pipeline triggers automatically on any push to the `main` branch.

---

## Entra ID App Registration & RBAC

An **Azure AD App Registration** is provisioned automatically by Terraform (`terraform/entra_app.tf`) to allow Kafka/Avro clients to authenticate via OAuth2 (OAUTHBEARER) and access the Schema Registry.

### What is created

| Resource | Purpose |
|---|---|
| `azuread_application` | App Registration (`app-eventhub-kafka-client`) |
| `azuread_service_principal` | Service Principal for the app |
| `azuread_application_password` | Client secret used as Kafka password |
| RBAC: `Azure Event Hubs Data Sender` | Allows the app to **produce** messages |
| RBAC: `Azure Event Hubs Data Receiver` | Allows the app to **consume** messages |
| RBAC: `Schema Registry Contributor (Preview)` | Allows the app to read/write Avro schemas |

### Authentication Flow

Kafka clients authenticate using **SASL/OAUTHBEARER**. The client fetches a token from:
```
https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token
```
with scope `https://eventhubs.azure.net/.default`, using the App Registration's `client_id` and `client_secret`.

The Schema Registry (exposed on port 443 via the Application Gateway) uses **HTTP Basic Auth** with the same `client_id:client_secret` credentials.

---

## Kafka Client Credentials (stored in Key Vault)

After `terraform apply`, credentials and the fully rendered `client.properties` are automatically stored in Key Vault:

| Secret Name | Description |
|---|---|
| `kafka-client-secret` | App Registration client secret |
| `kafka-client-properties` | Fully rendered `client.properties` — ready to use |

The `kafka_client_id` (public identifier) is available directly as a Terraform output.

Retrieve the ready-to-use `client.properties` via the **Download client.properties** GitHub Actions workflow (**Actions → Download client.properties → Run workflow**) — the file is uploaded as a build artifact with a 10-day retention.

Access is controlled by Key Vault RBAC — grant `Key Vault Secrets User` to any identity that needs to read the credentials.

---

## Client Configuration (`client.properties`)

All Kafka and Schema Registry connection settings are in a single `client.properties` file — the standard Confluent/Kafka CLI format, directly compatible with **Pega's Kafka connector** and all Confluent tools (`kafka-avro-console-producer`, `kafka-avro-console-consumer`, Confluent CLI).

Terraform renders the file with real values after each deployment and stores it in Key Vault. Retrieve it via the **Download client.properties** GitHub Actions workflow (**Actions → Download client.properties → Run workflow**).

A placeholder template is also committed at `kafka/client.properties` for reference.

> ⚠️ **Never commit the populated `client.properties` to source control.** Only the template (with placeholders) is safe to commit.

---

## Avro Schema & Topic

### Topic Naming (Confluent Convention)

| Component | Value |
|---|---|
| Topic name | `orders.placed` |
| Schema subject | `orders.placed-value` (Confluent **TopicNameStrategy** — default) |
| Schema group | `orders-schema-group` |

> **TopicNameStrategy** (the Confluent default) derives the subject from the topic name: `<topic>-value`. No extra client configuration is needed.

### Avro Schema (`orders.placed-value`)

```json
{
  "type": "record",
  "name": "OrderPlaced",
  "namespace": "se.thruput.orders",
  "fields": [
    { "name": "order_id",  "type": "string" },
    { "name": "product",   "type": "string" },
    { "name": "quantity",  "type": "int"    },
    { "name": "timestamp", "type": "long"   }
  ]
}
```

The schema is registered automatically by the **Confluent Endpoint Check** workflow (`confluent-endpoint-check.yml`) under the subject `orders.placed-value`.

---

## Post-Deploy Validation

### Terraform Check Block (`terraform/check_kafka.tf`)

Following Terraform best practice, a `check` block runs automatically after every `terraform apply`. It asserts that the Schema Registry endpoint is reachable and returns HTTP 200 — a lightweight, idiomatic health check with no external dependencies.

> The `check` block is non-blocking: a failure raises a warning but does not fail the apply. DNS must resolve `eventhub.thruput.se` to the Application Gateway public IP before the check runs.

### Full Confluent Endpoint Check (GitHub Actions)

For a full end-to-end Confluent validation — schema registration, Avro produce, and Avro consume — run the **Confluent Endpoint Check** workflow:

**Actions → Confluent Endpoint Check → Run workflow** (enter your custom domain)

This workflow uses `confluentinc/cp-schema-registry:7.6.0` with standard Confluent tooling (`kafka-avro-console-producer` / `kafka-avro-console-consumer`) and the `jaas.properties` pattern, connecting via the public Application Gateway endpoints.

---

## Key Infrastructure Components

| File | Purpose |
|---|---|
| `terraform/main.tf` | VNet, Subnets, Resource Group |
| `terraform/eventhub.tf` | Event Hub Namespace, Private Endpoint, DNS |
| `terraform/appgateway.tf` | Application Gateway (L4 + L7 listeners) |
| `terraform/keyvault.tf` | Key Vault, PFX cert, Managed Identity, Secret storage |
| `terraform/providers.tf` | Provider versions, remote state |
| `terraform/variables.tf` | Input variables |
| `terraform/entra_app.tf` | App Registration, Service Principal, RBAC, KV secret |
| `terraform/schema_registry.tf` | Event Hub topic and Schema Group |
| `terraform/check_kafka.tf` | Smoke test + Terraform check block |
| `kafka/client.properties` | Client config template for Pega and other Java/Confluent clients |

## Important Notes

- **L4 Proxy**: This POC utilizes the TLS proxy feature of Application Gateway. Ensure your client supports SNI and matches the `custom_domain_name` configured.
- **DNS**: After deployment, you must create a CNAME or A record in your DNS provider for your `custom_domain_name` pointing to the Application Gateway's Public IP FQDN or IP address.
- **TLS Certificate**: The certificate is issued by a public CA and is trusted by all standard JVM truststores (including Pega) out of the box — no manual import required.
