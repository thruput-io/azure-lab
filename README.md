# Azure Event Hub + Apicurio Schema Registry behind Application Gateway (PoC)

This Proof of Concept exposes **Azure Event Hubs** (Kafka endpoint) and **Apicurio Schema Registry** (Confluent-compatible API) through an **Azure Application Gateway**, keeping the Event Hubs namespace private via Private Link.

The goal is to validate a configuration that external clients — starting with **Pega Cloud** — can use with standard Confluent Kafka client libraries and Avro schema support.

See [`goals.md`](goals.md) for full objectives and phase definitions.  
See [`PegaSetup.md`](PegaSetup.md) for the Pega integration guide.  
See [`poc-outcome.md`](poc-outcome.md) for the full PoC outcome and findings.

---

## Architecture

```
Internet
   │
   ▼
Application Gateway v2 (public IP, custom domain)
   ├── :443  (L7 HTTPS)  → Apicurio Schema Registry (ACI)
   ├── :5671 (L4 TLS)    → Event Hubs AMQP
   └── :9093 (L4 TLS)    → Event Hubs Kafka
                                │
                         Private Endpoint
                                │
                         Event Hubs Namespace
                         (Standard SKU, VNet isolated)
```

**Kafka broker auth:** `SASL/PLAIN` with `$ConnectionString`  
**Schema Registry auth:** Entra ID OAuth2 (`bearer.auth.*` client credentials flow)  
**Schema Registry API:** Confluent-compatible (`/apis/ccompat/v7`)

> **Platform constraint:** Azure Event Hubs port 9093 supports **only SASL/PLAIN with `$ConnectionString`** for Kafka clients. `SASL/OAUTHBEARER` is not supported on the Kafka endpoint (tested and confirmed, see `deviations.md` DEV-001).

---

## Features

- **Private Event Hubs namespace** in a VNet using Private Endpoint + Private DNS.
- **Application Gateway endpoints:**
  - `:9093` TLS proxy for Kafka clients (SASL/PLAIN)
  - `:443` HTTPS route to Apicurio Schema Registry
  - `:5671` TLS proxy for AMQP clients
- **Apicurio Schema Registry** on Azure Container Instances, secured with Entra ID OIDC.
- **Custom domain + Key Vault certificate** managed by Application Gateway.
- **Two self-contained client properties files** delivered via GitHub Actions artifact.

---

## Prerequisites

- An Azure subscription.
- A PFX certificate for your custom domain.
- A custom domain name pointing to Application Gateway public IP/FQDN.

---

## Deployment

### GitHub Actions

Automated Terraform deployment via the **Terraform Deploy** workflow.

#### CI/CD prerequisites

1. Create an Azure service principal with `Contributor` access and GitHub OIDC trust.
2. Add repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `PFX_BASE64`
   - `PFX_PASSWORD`
3. Add repository variable:
   - `CUSTOM_DOMAIN_NAME` (e.g. `eventhub.example.com`)

After a successful deploy, the **Terraform Deploy** workflow also updates the `KAFKA_CLIENT_PROPERTIES` and `SCHEMA_CLIENT_PROPERTIES` GitHub secrets from Key Vault.

---

## Client Properties Files

After `terraform apply`, two self-contained properties files are stored in Key Vault and available via **Actions → Download client.properties → Run workflow**:

| File | Key Vault secret | Purpose |
|---|---|---|
| `kafka-client.properties` | `kafka-client-properties` | Kafka broker only (SASL/PLAIN) — JSON/text clients |
| `schema-client.properties` | `schema-client-properties` | Kafka broker + Schema Registry + OAuth — Avro clients |

> **These files are Terraform outputs — never local files in this repository.**  
> If a key is missing or wrong, fix `terraform/entra_app.tf` and redeploy.  
> See [`.ai/project_guidelines.md`](.ai/project_guidelines.md) for the full rule and background.

---

## Entra ID App Registrations

Terraform (`terraform/entra_app.tf`) provisions two app registrations:

| App | Purpose |
|---|---|
| `app-eventhub-kafka-client` | Kafka client identity — RBAC for Event Hubs produce/consume + SR admin role |
| `app-apicurio-registry` | Apicurio resource server — defines `sr-admin` / `sr-readonly` app roles |

The `schema-client.properties` file contains the `kafka-client` credentials and the Apicurio OAuth scope — it is self-contained for Avro clients.

---

## Post-Deploy Validation

Run the smoke tests via GitHub Actions:

- **Schema Tests** (`schema-tests.yml`) — Avro produce + consume round-trip against Apicurio:
  - Check 1: Connectivity + SSL
  - Check 2: Authentication (OAuth + Kafka)
  - Check 3: Avro Produce + Consume

Or run locally (requires a runtime `schema-client.properties` from the artifact):

```bash
./scripts/schema-check.sh --props-file /path/to/schema-client.properties
./scripts/kafka-check.sh  --props-file /path/to/kafka-client.properties
```

---

## Key Infrastructure Files

| File | Purpose |
|---|---|
| `terraform/main.tf` | VNet, subnets, resource group |
| `terraform/eventhub.tf` | Event Hubs namespace, private endpoint, private DNS |
| `terraform/appgateway.tf` | Application Gateway listeners, rules, backends |
| `terraform/keyvault.tf` | Key Vault, certificate, managed identity |
| `terraform/entra_app.tf` | App registrations, RBAC, rendered client properties (source of truth) |
| `terraform/apicurio.tf` | Apicurio Schema Registry on ACI |
| `terraform/schema_registry.tf` | Event Hub topics |
| `terraform/providers.tf` | Provider versions and backend config |
| `terraform/variables.tf` | Input variables |
| `scripts/kafka-check.sh` | Kafka connectivity + produce/consume smoke test |
| `scripts/schema-check.sh` | Avro produce + consume smoke test (schema pre-registration + native SR OAuth) |
| `.github/workflows/schema-tests.yml` | CI schema validation workflow |
| `.github/workflows/download-client-properties.yml` | Deliver client properties as artifact |

---

## Important Notes

- **L4 proxying** requires clients that support SNI for `CUSTOM_DOMAIN_NAME`.
- **DNS** must be configured after deployment for the custom domain.
- **TLS certificate** is served by Application Gateway from Key Vault.
- **SASL/OAUTHBEARER** is not supported on the Azure Event Hubs Kafka endpoint — use SASL/PLAIN with `$ConnectionString` (see `deviations.md` DEV-001).
