---

### Guideline: `kafka-client.properties` and `schema-client.properties` are the Single Source of Truth

> **`kafka-client.properties` and `schema-client.properties` are generated exclusively by Terraform (`entra_app.tf`) and stored in Key Vault. They must never be hand-edited, hardcoded in scripts, or mutated by any agent, workflow step, or test.**

---

#### What this means in practice

- **Scripts and tests** (`kafka-check.sh`, `schema-check.sh`, GitHub Actions workflows) must accept the relevant properties file as their **only input** and pass it as-is to tools. They must not construct, override, or supplement any property values internally.

- **All connection parameters** (bootstrap servers, SASL mechanism, JAAS config, topics, schema registry URL, OAuth credentials) must originate from a Terraform resource in `entra_app.tf`. No values may be hardcoded in scripts, workflow YAML, or documentation that will be treated as authoritative.

- **The two canonical properties files** are:
  - `kafka-client.properties` — Kafka broker settings + topics only (SASL/PLAIN + `$ConnectionString`). Key Vault secret: `kafka-client-properties`. GitHub secret: `KAFKA_CLIENT_PROPERTIES`.
  - `schema-client.properties` — Schema Registry URL + Kafka broker + OAuth credentials (self-contained, `oauth.client.secret` included in cleartext). Key Vault secret: `schema-client-properties`. GitHub secret: `SCHEMA_CLIENT_PROPERTIES`.
  - Both are downloaded via the "Download client.properties" GitHub Action as separate artifacts.

- **The local placeholder files** `kafka/kafka-client.properties` and `kafka/schema-client.properties` in the repository are developer reference copies only — they are not authoritative. The canonical versions are the Key Vault secrets, accessed via the "Download client.properties" GitHub Action.

- **When an AI agent works on this repository**, it must not modify the local or downloaded properties files, must not add inline connection string literals to scripts, and must not introduce any property construction logic in shell scripts or workflows. If a required key is missing from a properties file, the fix goes into `entra_app.tf`, not into the consuming script.

---

#### Allowed vs. not allowed

| ✅ Allowed                                                                           | ❌ Not allowed                                                       |
|-------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Read a key from `kafka-client.properties` or `schema-client.properties` with `grep` | Build a `sasl.jaas.config` string inline in a script                |
| Add a new key to `entra_app.tf` and re-deploy                                       | Hardcode an endpoint, topic name, or credential in a workflow YAML  |
| Validate that a required key exists in the properties file                          | Overwrite or regenerate a properties file from within a test/script |
| Pass the properties file directly to a tool via `-v`/`--config`                     | Merge two property sources (e.g., file + env var) inside a script   |

---

#### Enforcement checklist (for code review / AI agent self-check)

1. Does any script contain a literal `PlainLoginModule`, `OAuthBearerLoginModule`, connection string, tenant ID, or client ID? → **Move it to `entra_app.tf`.**
2. Does any workflow step construct a properties file from secrets or env vars (other than writing `$KAFKA_CLIENT_PROPERTIES` or `$SCHEMA_CLIENT_PROPERTIES` verbatim to disk)? → **Not allowed.**
3. Are `kafka-client.properties` or `schema-client.properties` committed to git with real credentials? → **Not allowed; the committed files are placeholders only.**
4. Does a new script parameter bypass the properties files for any Kafka or Schema Registry setting? → **Not allowed.**

---

**The plan must NOT be updated during implementation.** If an implementation decision deviates from the plan, record it in `deviations.md` instead. Only update the plan between implementation phases when a deliberate architectural change is agreed upon.

## Read goals.md to not loose track of goals
