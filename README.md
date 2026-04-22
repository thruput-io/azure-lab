# Azure Event Hub behind Application Gateway (POC)

This Proof of Concept (POC) exposes **Azure Event Hubs** through an **Azure Application Gateway** while keeping the Event Hubs namespace private through Private Link.

## Features

- **Private Event Hubs namespace** in a VNet using Private Endpoint + Private DNS.
- **Application Gateway endpoints**:
  - `:443` HTTPS route to Event Hubs HTTPS endpoint.
  - `:5671` TLS proxy for AMQP clients.
  - `:9093` TLS proxy for Kafka clients.
- **Custom domain + Key Vault certificate** managed by Application Gateway.
- **Entra ID OAuth2** for Kafka clients (`SASL/OAUTHBEARER`).

## Architecture

```
Internet
   │
   ▼
Application Gateway v2 (public IP, custom domain)
   ├── :443  (L7 HTTPS)  → Event Hubs HTTPS endpoint
   ├── :5671 (L4 TLS)    → Event Hubs AMQP
   └── :9093 (L4 TLS)    → Event Hubs Kafka
                                │
                         Private Endpoint
                                │
                         Event Hubs Namespace
                         (Standard SKU, VNet isolated)
```

Authentication: **SASL/OAUTHBEARER** (Kafka)  
Token issuer: `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token`

## Prerequisites

- An Azure subscription.
- A PFX certificate for your custom domain.
- A custom domain name pointing to Application Gateway public IP/FQDN.

## Deployment

### GitHub Actions

This project includes an automated Terraform deployment workflow.

#### CI/CD prerequisites

1. Create an Azure service principal with `Contributor` access and GitHub OIDC trust.
2. Add repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `PFX_BASE64`
   - `PFX_PASSWORD`
3. Add repository variable:
   - `CUSTOM_DOMAIN_NAME` (for example `eventhub.example.com`).

---

## Entra ID App Registration & RBAC

Terraform (`terraform/entra_app.tf`) provisions an app registration for Kafka clients.

| Resource | Purpose |
|---|---|
| `azuread_application` | App registration (`app-eventhub-kafka-client`) |
| `azuread_service_principal` | Service principal for the app |
| `azuread_application_password` | Client secret used by Kafka clients |
| RBAC: `Azure Event Hubs Data Sender` | Produce permission |
| RBAC: `Azure Event Hubs Data Receiver` | Consume permission |

Kafka clients request tokens from:

```
https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token
```

with scope `https://eventhubs.azure.net/.default`.

---

## Kafka Client Credentials (stored in Key Vault)

After `terraform apply`, the following secrets are written to Key Vault:

| Secret Name | Description |
|---|---|
| `kafka-client-secret` | App registration client secret |
| `kafka-client-properties` | Rendered Kafka `client.properties` |

Download the rendered `client.properties` via the **Download client.properties** workflow artifact.

> ⚠️ Never commit populated credentials to source control.

---

## Client Configuration (`client.properties`)

`client.properties` contains Kafka bootstrap and OAuth settings for Event Hubs Kafka access through Application Gateway (`:9093`).

Template file: `kafka/client.properties`

---

## Post-Deploy Validation

- Confirm DNS for `CUSTOM_DOMAIN_NAME` points to Application Gateway.
- Confirm TCP reachability to Kafka endpoint `CUSTOM_DOMAIN_NAME:9093`.
- Run your producer/consumer smoke tests with the downloaded `client.properties`.

---

## Key Infrastructure Components

| File | Purpose |
|---|---|
| `terraform/main.tf` | VNet, subnets, resource group |
| `terraform/eventhub.tf` | Event Hubs namespace, private endpoint, private DNS |
| `terraform/appgateway.tf` | Application Gateway listeners/rules/backends |
| `terraform/keyvault.tf` | Key Vault, certificate, managed identity, secrets |
| `terraform/providers.tf` | Provider versions and backend config |
| `terraform/variables.tf` | Input variables |
| `terraform/entra_app.tf` | App registration, RBAC, rendered client properties |
| `terraform/schema_registry.tf` | Event Hub topic and schema group resources |
| `kafka/client.properties` | Kafka client config template |

## Important Notes

- **L4 proxying** requires clients that support SNI for `custom_domain_name`.
- **DNS** must be configured after deployment for the custom domain.
- **TLS certificate** is served by Application Gateway from Key Vault.
