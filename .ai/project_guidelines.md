---

### Guideline: `kafka-client.properties` and `schema-client.properties` are Terraform outputs — never local files

> **`kafka-client.properties` and `schema-client.properties` are generated exclusively by Terraform (`entra_app.tf`) and stored in Key Vault. They are NOT files in this repository. No AI agent, developer, or workflow may ever create, commit, or maintain local copies of these files.**

---

#### Why this rule exists — background for AI agents

The entire purpose of this project is to build working PoC infrastructure so that **external clients can connect and test it**. The properties files are the **end product** of that infrastructure: they are what an external client receives to connect. They are not configuration inputs — they are Terraform outputs.

When a local `.properties` file exists in the repository — even as a "placeholder" — every AI agent that opens the project treats it as the authoritative source of truth. The AI then reads it, decides something is wrong or missing, and **fixes the local file** instead of fixing Terraform. This is exactly backwards: the local file is a lie. It does not represent what the real runtime file contains. It just wastes AI effort on the wrong artifact and produces nothing useful for external clients.

The only way to produce a correct, working properties file is to fix `entra_app.tf` and redeploy. That is the whole point.

---

#### The only valid lifecycle of these files

1. **Terraform** (`entra_app.tf`) defines their content as Key Vault secrets (`kafka-client-properties`, `schema-client-properties`).
2. **GitHub Actions** ("Download client.properties" workflow) fetches them from Key Vault at runtime and writes them to disk temporarily for use by scripts.
3. **Scripts** (`kafka-check.sh`, `schema-check.sh`) receive the file path as `--props-file` argument and pass it as-is to tools. They never construct, override, or supplement any property values.

There is no step 0 where a human or AI creates a local file. If a key is missing or wrong, the fix is always in `entra_app.tf`.

---

#### STRICTLY FORBIDDEN — no exceptions, no "placeholder" exceptions

- **Creating any local `.properties` file** in the repository, including files named `kafka-client.properties`, `schema-client.properties`, `client.properties`, or any variant — even as a "placeholder", "reference copy", "developer convenience", or "template". These files have historically caused AIs to treat them as authoritative and waste effort "fixing" them instead of fixing Terraform.
- Building a `sasl.jaas.config`, OAuth token request, or any credential string inline in a script or workflow.
- Hardcoding any endpoint, topic name, tenant ID, client ID, connection string, or credential anywhere outside `entra_app.tf`.
- Merging two property sources (e.g., file + env var) inside a script.
- Overwriting or regenerating a properties file from within a test, script, or workflow (other than writing `$KAFKA_CLIENT_PROPERTIES` or `$SCHEMA_CLIENT_PROPERTIES` verbatim to disk in GitHub Actions).

---

#### What this means in practice

- **Scripts and tests** must accept the relevant properties file as their **only input** and pass it as-is to tools.
- **All connection parameters** (bootstrap servers, SASL mechanism, JAAS config, topics, schema registry URL, OAuth credentials) must originate from a Terraform resource in `entra_app.tf`.
- **The two canonical properties files** are:
  - `kafka-client.properties` — Kafka broker settings + topics only (SASL/PLAIN + `$ConnectionString`). Key Vault secret: `kafka-client-properties`. GitHub secret: `KAFKA_CLIENT_PROPERTIES`.
  - `schema-client.properties` — Schema Registry URL + Kafka broker + OAuth credentials (self-contained, `oauth.client.secret` included in cleartext). Key Vault secret: `schema-client-properties`. GitHub secret: `SCHEMA_CLIENT_PROPERTIES`.
  - Both are downloaded via the "Download client.properties" GitHub Action as separate artifacts.
- **When an AI agent works on this repository**, if a required key is missing from a properties file, the fix goes into `entra_app.tf`, not into the consuming script or a local file.

---

#### Allowed vs. not allowed

| ✅ Allowed                                                                           | ❌ Not allowed                                                       |
|-------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Read a key from the runtime properties file with `grep`                             | Create any local `.properties` file in the repo, even as placeholder |
| Add a new key to `entra_app.tf` and re-deploy                                       | Hardcode an endpoint, topic name, or credential in a script or YAML  |
| Validate that a required key exists in the properties file                          | Overwrite or regenerate a properties file from within a test/script |
| Pass the properties file directly to a tool via `-v`/`--config`                     | Merge two property sources (e.g., file + env var) inside a script   |

---

#### Enforcement checklist (for code review / AI agent self-check)

1. Does any script contain a literal `PlainLoginModule`, `OAuthBearerLoginModule`, connection string, tenant ID, or client ID? → **Move it to `entra_app.tf`.**
2. Does any workflow step construct a properties file from secrets or env vars (other than writing `$KAFKA_CLIENT_PROPERTIES` or `$SCHEMA_CLIENT_PROPERTIES` verbatim to disk)? → **Not allowed.**
3. Is there any `.properties` file committed to git anywhere in the repository? → **Delete it. It must not exist.**
4. Does a new script parameter bypass the properties files for any Kafka or Schema Registry setting? → **Not allowed.**
5. Is an AI agent about to create a `kafka-client.properties` or `schema-client.properties` file locally? → **Stop. Fix `entra_app.tf` instead.**

---

#### Local Docker testing — allowed and encouraged for diagnostics

AI agents and developers are **free to run Confluent Docker images locally** (`confluentinc/cp-schema-registry:8.2.0`, `confluentinc/cp-kafka:8.2.0`) to test endpoints, verify Apicurio connectivity, and diagnose OAuth/schema issues. This is the correct way to validate infrastructure before committing Terraform changes.

**The rules during a Docker test session:**

- ✅ Run `docker run confluentinc/cp-schema-registry:8.2.0 kafka-avro-console-producer/consumer ...` with a runtime properties file passed via `-v`
- ✅ Use `curl` or `docker exec` to probe Apicurio endpoints (`/apis/ccompat/v7/subjects`, `/health`, etc.)
- ✅ Experiment with different property values to find what works
- ✅ Once the correct configuration is confirmed → **update `entra_app.tf`** to reflect it permanently
- ❌ Do NOT save any working config discovered during testing into a local `.properties` file
- ❌ Do NOT hardcode anything discovered during testing into a script or workflow
- ❌ Do NOT commit any test artifacts, temp files, or credentials

**The mental model:** Docker testing is **read-only from the repo's perspective.** You run it, you learn something, you fix `entra_app.tf`. The only thing that flows back into the repo is a Terraform change. The properties files that external clients receive are always the product of that Terraform change — never of a local experiment.

---

**The plan must NOT be updated during implementation.** If an implementation decision deviates from the plan, record it in `deviations.md` instead. Only update the plan between implementation phases when a deliberate architectural change is agreed upon.

## Read goals.md to not lose track of goals
