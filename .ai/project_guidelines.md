---

### Guideline: `client.properties` is the Single Source of Truth

> **`client.properties` is generated exclusively by Terraform (`entra_app.tf`) and stored in Key Vault. It must never be hand-edited, hardcoded in scripts, or mutated by any agent, workflow step, or test.**

---

#### What this means in practice

- **Scripts and tests** (`kafka-check.sh`, `schema-check.sh`, GitHub Actions workflows) must accept `client.properties` as their **only input** and pass it as-is to tools. They must not construct, override, or supplement any property values internally.

- **All connection parameters** (bootstrap servers, SASL mechanism, JAAS config, topics, schema registry URL, OAuth credentials) must originate from a Terraform resource in `entra_app.tf`. No values may be hardcoded in scripts, workflow YAML, or documentation that will be treated as authoritative.

- **The local `client.properties` file in the repository root** is a developer convenience copy only — it is not authoritative. The canonical version is the Key Vault secret `kafka-client-properties`, accessed via the "Download client.properties" GitHub Action.

- **When an AI agent works on this repository**, it must not modify `client.properties` (local or downloaded), must not add inline connection string literals to scripts, and must not introduce any property construction logic in shell scripts or workflows. If a required key is missing from `client.properties`, the fix goes into `entra_app.tf`, not into the consuming script.

---

#### Allowed vs. not allowed

| ✅ Allowed | ❌ Not allowed |
|---|---|
| Read a key from `client.properties` with `grep` | Build a `sasl.jaas.config` string inline in a script |
| Add a new key to `entra_app.tf` and re-deploy | Hardcode an endpoint, topic name, or credential in a workflow YAML |
| Validate that a required key exists in `client.properties` | Overwrite or regenerate `client.properties` from within a test/script |
| Pass `client.properties` directly to a tool via `-v`/`--config` | Merge two property sources (e.g., file + env var) inside a script |

---

#### Enforcement checklist (for code review / AI agent self-check)

1. Does any script contain a literal `PlainLoginModule`, `OAuthBearerLoginModule`, connection string, tenant ID, or client ID? → **Move it to `entra_app.tf`.**
2. Does any workflow step construct a properties file from secrets or env vars (other than writing `$KAFKA_CLIENT_PROPERTIES` verbatim to disk)? → **Not allowed.**
3. Is `client.properties` committed to git with real credentials? → **Not allowed; the committed file is a placeholder only.**
4. Does a new script parameter bypass `client.properties` for any Kafka or Schema Registry setting? → **Not allowed.**

---

### Guideline: Refer to `Apicurio_schema_registry_plan.md` for Schema Registry Architecture

The file `Apicurio_schema_registry_plan.md` (project root) is the authoritative plan for the Apicurio Schema Registry PoC deployment. It documents all architecture decisions, implementation steps, traffic flow, and the split between `kafka-client.properties` and `schema-client.properties`.

**AI agents and contributors must read this file before:**
- Modifying anything in `terraform/apicurio.tf`, `terraform/schema_registry.tf`, or the schema-related blocks in `terraform/entra_app.tf`.
- Modifying `scripts/schema-check.sh` or `.github/workflows/schema-tests.yml`.
- Changing App Gateway L7 (port 443) backend routing.
- Adding or removing Key Vault secrets related to schema registry.

**The plan must NOT be updated during implementation.** If an implementation decision deviates from the plan, record it in `deviations.md` instead. Only update the plan between implementation phases when a deliberate architectural change is agreed upon.

## Read goals.md to not loose track of goals
