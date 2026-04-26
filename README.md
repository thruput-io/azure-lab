# Azure Event Hub + Apicurio Schema Registry behind Application Gateway (PoC)

This Proof of Concept exposes **Azure Event Hubs** (Kafka endpoint) and **Apicurio Schema Registry** (Confluent-compatible API) through an **Azure Application Gateway**, keeping the Event Hubs namespace private via Private Link.

The goal is to validate a configuration that external clients — starting with **Pega Cloud** — can use with standard Confluent Kafka client libraries and JSON Schema support.

See [`goals.md`](goals.md) for full objectives and phase definitions.  
See [`PegaSetup.md`](PegaSetup.md) for the Pega integration guide.

---

## Architecture

```
Internet
   │
   ▼
Application Gateway v2 (public IP, custom domain)
   ├── :443  (L7 HTTPS)  → Apicurio Schema Registry (ACI)
   └── :9093 (L4 TLS)    → Event Hubs Kafka
                                │
                         Private Endpoint
                                │
                         Event Hubs Namespace
                         (Standard SKU, VNet isolated)
```

**Kafka broker auth:** `SASL/OAUTHBEARER` (OIDC)  
**Schema Registry auth:** Entra ID OAuth2 (`bearer.auth.*` client credentials flow)  
**Schema Registry API:** Confluent-compatible (`/apis/ccompat/v7`)

---

## Features

- **Private Event Hubs namespace** in a VNet using Private Link.
- **Application Gateway endpoints:**
  - `:9093` TLS proxy for Kafka clients (SASL/OAUTHBEARER)
  - `:443` HTTPS route to Apicurio Schema Registry
- **Apicurio Schema Registry** on Azure Container Instances, secured with Entra ID OIDC.
- **Custom domain + Key Vault certificate** managed by Application Gateway.
- **Single self-contained client.properties file** delivered via GitHub Actions artifact.

---

## Prerequisites

- An Azure subscription.
- A custom domain name pointing to Application Gateway public IP.

---

## Deployment

### GitHub Actions

Automated Terraform deployment via the **Terraform Deploy** workflow.

#### CI/CD prerequisites

1. Create an Azure service principal with `Contributor` access and GitHub OIDC trust.
2. Add repository secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).
3. Add repository variable: `CUSTOM_DOMAIN_NAME`.

After a successful deploy, the **Terraform Deploy** workflow also updates the `KAFKA_CLIENT_PROPERTIES` GitHub secret from Key Vault.

---

## Client Properties File

After `terraform apply`, the self-contained `client.properties` file is stored in Key Vault and available via **Actions → Download client.properties**:

| File | Key Vault secret | Purpose |
|---|---|---|
| `client.properties` | `client-properties` | Kafka broker + Schema Registry + OAuth — JSON Schema clients |

> **This file is a Terraform output — never a local file in this repository.**  
> If a key is missing or wrong, fix `terraform/modules/kafka/client-config/main.tf` and redeploy.  
> See [`.ai/project_guidelines.md`](.ai/project_guidelines.md) for the full rule and background.

---

## Post-Deploy Validation

Run the smoke tests via GitHub Actions:

- **Kafka Tests** (`kafka-tests.yml`) — JSON Schema produce + consume round-trip:
  - Check 1: Connectivity + SSL
  - Check 2+3: Auth + Produce/Consume (`scripts/kafka-check.sh`)

Or run locally (requires a runtime `client.properties` from the artifact):

```bash
./scripts/kafka-check.sh --props-file /path/to/client.properties
```

---

## Key Infrastructure Files

| File | Purpose |
|---|---|
| `terraform/main.tf` | Root module |
| `terraform/modules/kafka/main.tf` | Event Hubs + App Registration + RBAC |
| `terraform/modules/kafka/client-config/main.tf` | Rendered client.properties (single source of truth) |
| `terraform/modules/kafka/schema-registry/main.tf` | Apicurio Schema Registry on ACI |
| `scripts/kafka-check.sh` | Kafka + JSON Schema connectivity smoke test |
| `.github/workflows/kafka-tests.yml` | CI validation workflow |
