# Apicurio Schema Registry — PoC Plan

## Goal

Replace Azure Event Hubs Schema Registry (not Confluent-compatible) with Apicurio Registry, exposed via the existing Application Gateway. Verify that Confluent clients (cp-schema-registry) can authenticate using Entra ID OAuth tokens and perform Avro schema produce/consume round-trips.

Kafka connectivity (port 9093) is not affected.

---

## Architecture Decisions

### Compute
- **Azure Container Instances (ACI)** — smallest, fully managed container runner. No cluster or orchestrator. One Terraform resource: `azurerm_container_group`.

### Database
- **PostgreSQL sidecar container** — runs as a second container inside the same `azurerm_container_group` as Apicurio. No persistent volume (PoC only — data is ephemeral). No managed service, no delegated subnet. Connection string uses `localhost:5432` since containers in the same ACI group share the network namespace.

### Networking
- ACI is deployed in the **same VNet as Event Hub**, in a dedicated delegated subnet (`snet-aci`).
- No `snet-pg` subnet is needed (PostgreSQL runs in the same ACI group as Apicurio).
- Same private-link pattern as Event Hub.
- **TLS terminated at App Gateway** using the existing `managed-cert` (same hostname: `eventhub.grayskull.se`).
- App Gateway forwards **plain HTTP on port 8080** to the ACI container (no end-to-end TLS for PoC).

### Port 443 / App Gateway
- The existing L7 HTTPS listener (port 443, `eventhub.grayskull.se`) is **redirected from Event Hub REST to Apicurio**.
- Event Hub REST API (`:443 → servicebus.windows.net`) is unpublished — it was only reachable via App Gateway.
- Kafka (9093) and AMQP (5671) L4 rules are **not changed**.
- Routing rule stays `Basic` (no path rewriting). All URIs pass through as-is.

### Confluent Schema Registry Compatibility
- Apicurio exposes the Confluent-compatible API at `/apis/ccompat/v7` (built-in, always enabled in 3.x).
- No App Gateway path rewrite is needed — client sets:
  ```
  schema.registry.url=https://eventhub.grayskull.se/apis/ccompat/v7
  ```

### Authentication
- Apicurio is registered as an **Entra ID application** (`app-apicurio-registry`).
- Apicurio is configured with `QUARKUS_OIDC_*` environment variables pointing to the Entra ID OIDC endpoint.
- Token type: `id` (`REGISTRY_AUTH_TOKEN_TYPE=id`) — required for Entra ID.
- App roles defined on the Apicurio app registration (e.g., `sr-admin`) map to Apicurio RBAC roles.
- Scope used by schema clients: `api://<apicurio_client_id>/Registry.Access`

### Client Properties Files

> ⛔ **These files do NOT exist in the repository. They must NEVER be created locally — not even as placeholders, templates, or reference copies. Any local `.properties` file is a lie: it misleads AIs and developers into "fixing" it instead of fixing Terraform. The only valid source is `entra_app.tf` → Key Vault → GitHub Actions download.**

Two separate files, both generated exclusively by `entra_app.tf` and stored in Key Vault. Neither is hand-edited, committed to git, or mutated by scripts.

| File | Key Vault secret | GitHub secret | Purpose |
|---|---|---|---|
| `kafka-client.properties` | `kafka-client-properties` | `KAFKA_CLIENT_PROPERTIES` | Kafka broker only (SASL/PLAIN + $ConnectionString) |
| `schema-client.properties` | `schema-client-properties` | `SCHEMA_CLIENT_PROPERTIES` | Schema Registry + Kafka broker + OAuth (self-contained, `oauth.client.secret` included in cleartext) |

The "Download client.properties" GitHub Action delivers **both** files as separate artifacts at runtime. They are never at rest in the repository.

**If a key is missing or wrong in either file → fix `entra_app.tf` and redeploy. Never create a local file.**

### Confluent Docker Image Version
- All test scripts and workflows use **`confluentinc/cp-kafka:8.2.0`** and **`confluentinc/cp-schema-registry:8.2.0`**.

---

## Implementation Steps

### Step 0 — Establish Baseline (run before any changes)
- Run 'Kafka Tests' action (`kafka-tests.yml`) — must pass. This is the known-good baseline.
- Run "Download client.properties" action (`download-client-properties.yml`) — artifact must download successfully and contain `bootstrap.servers`.
- **Verification:** Both actions pass. No changes are made in this step. Do not proceed to Step 1 until both are green.

### Step 1 — Rename `client.properties` to `kafka-client.properties`
- Strip schema/oauth props from `kafka-client-properties` KV secret — Kafka broker settings + topics only.
- Rename placeholder file `kafka/client.properties` → `kafka/kafka-client.properties`.
- Add new placeholder `kafka/schema-client.properties`.
- Update `download-client-properties.yml` to deliver both files as separate artifacts.
- Update `deploy.yml` to push both `KAFKA_CLIENT_PROPERTIES` and `SCHEMA_CLIENT_PROPERTIES` GitHub secrets post-deploy.
- **Verification:** Run "Download client.properties" action — two artifacts downloaded (`kafka-client.properties` + `schema-client.properties`). Run 'Kafka Tests' action — still passes.

### Step 2 — Fix `schema-check.sh` to follow guidelines
- Remove internal SASL/PLAIN property construction (lines 124–130 that build a temp props file with hardcoded `PlainLoginModule` — guideline violation).
- `schema-check.sh` accepts `--props-file schema-client.properties` as its only input.
- All Kafka auth, SR URL, and OAuth props come from that file. No inline construction.
- Update `schema-tests.yml` to use `SCHEMA_CLIENT_PROPERTIES` secret → write to `schema-client.properties`.
- **Verification:** Run 'Kafka Tests' action — still passes. Run "Download client.properties" action — both artifacts still delivered. `schema-tests.yml` run reflects correct structure (will fail at connectivity since Apicurio not yet deployed — that is expected and acceptable).

### Step 3 — Remove Azure Event Hubs Schema Registry
- Remove `azurerm_eventhub_namespace_schema_group` from `schema_registry.tf`.
- Remove EH Schema Registry RBAC role assignments (`kafka_client_sr_reader`, `kafka_client_sr_contributor`) from `entra_app.tf`.
- Existing schemas are ignored — this is a PoC, not production.
- **Verification:** `deploy.yml` succeeds. Run 'Kafka Tests' action — still passes. Run "Download client.properties" action — both artifacts still delivered.

### Step 4 — Deploy Apicurio (new `terraform/apicurio.tf`)
- Add `snet-aci` (ACI delegation) subnet to `main.tf`.
- New `terraform/apicurio.tf`:
  - `azurerm_container_group` with **two containers**:
    - `postgres` sidecar (`postgres:16-alpine`, port 5432, ephemeral — no persistent volume)
    - `apicurio-registry` (`apicurio/apicurio-registry:3.x`, port 8080, connects to `localhost:5432`)
  - Apicurio `APICURIO_DATASOURCE_URL` = `jdbc:postgresql://localhost:5432/apicuriodb`
  - Entra OIDC env vars: `QUARKUS_OIDC_*`, `REGISTRY_AUTH_TOKEN_TYPE=id`, `APICURIO_AUTH_ROLE_BASED_AUTHORIZATION=true`
- New `azuread_application` for Apicurio in `entra_app.tf` with app roles and exposed API scope.
- New `schema-client-properties` Key Vault secret in `entra_app.tf` (includes `oauth.client.secret` inline — no side delivery).
- Update `appgateway.tf`: swap L7 443 backend from EH namespace pool to Apicurio ACI pool (HTTP :8080).
- **Verification:** `deploy.yml` succeeds. Apicurio `/apis/ccompat/v7/subjects` returns `[]` via curl. Run 'Kafka Tests' action — still passes. Run "Download client.properties" action — both artifacts still delivered.

### Step 5 — End-to-End Schema Tests
- Run 'Schema Tests' action with `SCHEMA_CLIENT_PROPERTIES`.
- Validate Entra OAuth token acquisition → Apicurio auth → Avro schema registration → Avro produce/consume round-trip.
- **Verification:** 'Schema Tests' action passes all checks. Run 'Kafka Tests' action — still passes. Run "Download client.properties" action — both artifacts delivered correctly.

---

## Traffic After Change

```
:443 HTTPS  →  App Gateway (TLS termination, managed-cert, eventhub.grayskull.se)
                    │
                    ▼ HTTP :8080
             Apicurio ACI (snet-aci)
             ┌─────────────────────────┐
             │  apicurio-registry :8080│
             │  postgres        :5432  │  ← sidecar, localhost only, ephemeral
             └─────────────────────────┘
                    │
       /apis/ccompat/v7/*  ← Confluent-compatible SR API
       /apis/registry/v3/* ← Native Apicurio API

:9093 TLS   →  Event Hub (L4 passthrough — UNCHANGED)
:5671 TLS   →  Event Hub (L4 passthrough — UNCHANGED)
```

---

## New / Changed Terraform Files

| File                           | Action                                                                                                        |
|--------------------------------|---------------------------------------------------------------------------------------------------------------|
| `terraform/main.tf`            | Add `snet-aci` delegated subnet (no `snet-pg` — PostgreSQL is a sidecar)                                      |
| `terraform/apicurio.tf`        | **New**: ACI container group with Apicurio + PostgreSQL sidecar                                               |
| `terraform/entra_app.tf`       | Add Apicurio app registration; strip schema props from kafka secret; add `schema-client-properties` KV secret |
| `terraform/appgateway.tf`      | Swap L7 443 backend: EH namespace → Apicurio ACI (HTTP :8080)                                                 |
| `terraform/schema_registry.tf` | Remove `azurerm_eventhub_namespace_schema_group` + EH SR RBAC                                                 |

## New / Changed Scripts and Workflows

| File                                               | Action                                                                                    |
|----------------------------------------------------|-------------------------------------------------------------------------------------------|
| `scripts/schema-check.sh`                          | Read all props from `--props-file` only; no inline construction                           |
| `.github/workflows/schema-tests.yml`               | Use `SCHEMA_CLIENT_PROPERTIES` + `schema-client.properties`                               |
| `.github/workflows/deploy.yml`                     | Add `SCHEMA_CLIENT_PROPERTIES` secret update step post-deploy                             |
| `.github/workflows/download-client-properties.yml` | Deliver both `kafka-client.properties` + `schema-client.properties` as separate artifacts |
| `kafka/client.properties`                          | Rename → `kafka/kafka-client.properties` (strip schema placeholders)                      |
| `kafka/schema-client.properties`                   | **New**: placeholder with schema + OAuth keys                                             |

---

## Process Rules

- **Do not update this file during implementation.** It is the frozen baseline.
- Any deviation from this plan (technical or scope) must be recorded in `deviations.md`.
- Each step above is a separate MR/PR with its own verification point.
- Before merging any PR, use available Agent Skills for review.
- Before starting each new step, re-read this file and `.ai/project_guidelines.md` to stay on track.
