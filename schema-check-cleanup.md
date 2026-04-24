# schema-check.sh — Cleanup Plan

> **Save location: project root (`schema-check-cleanup.md`)**
> **Status: Active — do not modify during implementation. Record deviations in `deviations.md`.**

---

## Why this plan exists

`schema-check.sh` currently works but is **not a valid test of `schema-client.properties`**.

The script:
1. Extracts `bearer.auth.*` credentials from the properties file
2. Makes an inline `curl` POST to acquire an Entra ID Bearer token
3. Injects the token as `--property bearer.auth.token=... (STATIC_TOKEN)` into the Docker command

This means the Confluent SR client **never reads `bearer.auth.*` from the properties file**.
The properties file is mounted via `-v`, but its OAuth keys are consumed by the script's `curl`
block — not by the SR client. The test passes, but it proves nothing about whether
`schema-client.properties` works as a self-contained config for Pega or any real Confluent
Avro client.

**The moment this was understood:** When asked "is `schema-client.properties` even referenced
in the produce/consume commands?" — it is mounted, but the SR client never reads its
`bearer.auth.*` keys because the script overrides them with `STATIC_TOKEN`. The file is
effectively ignored for auth purposes.

Additionally: `--property schema.registry.url="$SR_URL"` is passed on the CLI even though
`schema.registry.url` is already in the properties file. Every property that can live in the
file **must** live in the file — passing it again via `--property` creates a second source of
truth that can diverge from what Pega's real `kafka-avro-serializer` client would use.

---

## The goal

Remove the inline OAuth token acquisition from `schema-check.sh` so that:

- `schema-client.properties` is the **only** input
- The Confluent SR client reads `bearer.auth.*` natively from the properties file
- `--property schema.registry.url=...` is removed (it lives in the file already)
- The test proves that Pega can use the same file with `kafka-avro-serializer` / `kafka-avro-deserializer`
- No credential logic exists in the script

---

## Constraint (from `goals.md`)

> There is no value in setting up, testing, or documenting any schema registry feature,
> authentication flow, or client configuration that is **not supported by Confluent KafkaSerdes
> with schema support** (`kafka-avro-serializer` / `kafka-avro-deserializer`).
>
> If a workaround cannot be expressed as standard properties consumed by those serdes → fix
> the infrastructure instead. Never script around it.

---

## What the correct `schema-check.sh` must look like

```bash
# CORRECT — SR client reads bearer.auth.* and schema.registry.url natively from the properties file
echo "$TEST_MESSAGE" | docker run --rm -i \
  -v "$ABS_PROPS_FILE:/tmp/client.properties:ro" \
  "$IMAGE" \
  kafka-avro-console-producer \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --producer.config /tmp/client.properties \
    --property value.schema="$SCHEMA_DEF"
    # NO bearer.auth.token, NO STATIC_TOKEN, NO curl, NO schema.registry.url override
```

The `bearer.auth.credentials.source=OAUTHBEARER` (default) + `bearer.auth.issuer.endpoint.url`,
`bearer.auth.client.id`, `bearer.auth.client.secret`, `bearer.auth.scope` in the properties
file are read natively by the Confluent SR client library.

`schema.registry.url` is already in the properties file — no `--property` override needed.

---

## About `--property value.schema="$SCHEMA_DEF"`

This is **correct and expected** for `kafka-avro-console-producer`. It is a console tool
limitation — it has no application code to derive the schema from, so the schema must be
provided on the command line.

**Pega does NOT do this.** Pega's `kafka-avro-serializer` derives the schema from their
application code (generated Avro class or `Schema.Parser`). The serializer registers/looks up
the schema in Apicurio automatically. Pega only needs the properties file — no inline schema.

The inline schema in `schema-check.sh` is purely a console tool workaround. It does not
affect the validity of the properties file test.

---

## Pre-condition: Schema must be pre-registered before the test

`kafka-avro-console-producer` with `--property value.schema=...` will attempt to **register**
the schema in Apicurio on first use. To make the test deterministic and independent of
first-run registration, the schema should be pre-registered via a `curl` POST to Apicurio
**before** the produce step.

This is the **only place `curl` is allowed in the script** — it is a setup step (like a
database migration before a test), not an auth bypass. The token is acquired using
`bearer.auth.*` values from the properties file — the same values the SR client would use
natively. The token is used only for the pre-registration curl, not injected into the SR client.

```bash
# Step 0 — Pre-register schema (idempotent)
# Acquire token using bearer.auth.* from the properties file (same as SR client would)
# POST schema to /apis/ccompat/v7/subjects/<topic>-value/versions
# Accept HTTP 200 (registered) or 409 (already exists) as success
```

---

## Implementation Steps

### Step 1 — Verify native OAuth support via local Docker test

**Before touching any code**, confirm that `kafka-avro-console-producer` can authenticate to
Apicurio using only the properties file (no `--property bearer.auth.token=...` override).

Use a runtime `schema-client.properties` obtained from the "Download client.properties"
workflow artifact. **Do not create a local properties file** — ask the user to run the
workflow and share the artifact if you don't have it.

Expected test command (no `--property bearer.auth.*` overrides):
```bash
echo '{"order_id":"test","product":"x","quantity":1,"timestamp":1}' | \
  docker run --rm -i \
    -v /path/to/schema-client.properties:/tmp/client.properties:ro \
    confluentinc/cp-schema-registry:8.2.0 \
    kafka-avro-console-producer \
      --bootstrap-server eventhub.grayskull.se:9093 \
      --topic orders.placed \
      --producer.config /tmp/client.properties \
      --property value.schema='{"type":"record","name":"OrderPlaced","namespace":"io.thruput.orders","fields":[{"name":"order_id","type":"string"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"timestamp","type":"long"}]}'
```

**If it works** → proceed to Step 2.

**If it fails** → investigate which SR client property enables native OAuth for Entra ID.
The fix goes into `entra_app.tf` → `schema-client-properties` KV secret. **Not into the script.**
Re-run Step 1 after redeployment.

**Verification:** Producer and consumer succeed with no `--property bearer.auth.*` overrides
in the Docker command.

---

### Step 2 — Add schema pre-registration to `schema-check.sh`

Add a Step 0 block that:
1. Reads `bearer.auth.*` from the properties file
2. Acquires a token via `curl` (this is the only allowed curl in the script — setup only)
3. POSTs the schema to Apicurio `/apis/ccompat/v7/subjects/orders.placed-value/versions`
4. Accepts HTTP 200 (registered) or 409 (already exists) as success

This ensures the schema exists before the produce step, making the test deterministic.

**Verification:** Step 0 outputs `PASS: Schema pre-registered (or already exists)`.

---

### Step 3 — Remove inline STATIC_TOKEN and `schema.registry.url` override from `schema-check.sh`

Remove:
- `TOKEN_ENDPOINT`, `CLIENT_ID`, `CLIENT_SECRET`, `SCOPE` variable reads
- The entire `curl` token acquisition block (the current "Step 0" in the script)
- `--property bearer.auth.credentials.source=STATIC_TOKEN` (producer + consumer)
- `--property "bearer.auth.token=${ACCESS_TOKEN}"` (producer + consumer)
- `--property schema.registry.url="$SR_URL"` (producer + consumer) — it lives in the file
- `SR_URL` variable read (no longer needed in Docker commands; keep only for echo if desired)

Keep:
- `--producer.config /tmp/client.properties`
- `--consumer.config /tmp/client.properties`
- `--property value.schema="$SCHEMA_DEF"` (console tool requirement — not a KafkaSerdes concern)
- All validation, path resolution, echo, and consume-output parsing logic
- The key validation loop (must still check `bearer.auth.*` keys exist — they are required
  by the SR client, just not by the script)

**Verification:**
```bash
bash -n scripts/schema-check.sh  # Syntax OK
grep -n "STATIC_TOKEN\|bearer.auth.token\|ACCESS_TOKEN\|schema.registry.url" scripts/schema-check.sh
# Must return nothing (or only the key validation grep line, not --property overrides)
```

---

### Step 4 — Run Schema Tests

Push the cleaned script. Confirm the `Schema Tests` GitHub Actions workflow passes all checks:

- Check 1: Connectivity + SSL ✅
- Check 2: Authentication (OAuth + Kafka) ✅
- Check 3: Avro Produce + Consume ✅

**Verification:** All 3 checks green. No `STATIC_TOKEN` in logs. Schema pre-registration
step visible in Check 3 output.

---

## Rules for AI agents working on this plan

1. **Read `project_guidelines.md` before starting each step.** The guidelines contain hard
   stops that override any "it works" reasoning.

2. **Do not declare success based on CI passing alone.** The current script passes CI but
   violates the guidelines. The test is only valid if `schema-client.properties` is the
   actual source of auth — not a script-level curl workaround.

3. **If native OAuth doesn't work in Step 1** → the fix is in `entra_app.tf`, not in the
   script. Add the missing property to the `schema-client-properties` KV secret and redeploy.
   Do not add it to the script.

4. **Do not create local `.properties` files.** Step 1 requires a runtime properties file
   from the "Download client.properties" workflow artifact. If you don't have it, ask the
   user to run the workflow and share the artifact. Do not create a placeholder.

5. **The schema pre-registration curl in Step 2 is the only allowed curl in the script.**
   It is a setup step (like a database migration before a test), not an auth bypass. It uses
   the same `bearer.auth.*` values the SR client would use — it does not inject a token into
   the SR client.

6. **`--property schema.registry.url=...` must not appear in the Docker commands.** It lives
   in `schema-client.properties` already. Passing it again via `--property` creates a second
   source of truth and undermines the validity of the test.

7. **Do not update this plan during implementation.** Record deviations in `deviations.md`.

---

## Process Rules

- Each step is a separate commit with its own verification point.
- Before merging, re-read `project_guidelines.md` and this file.
- Docker testing is read-only from the repo's perspective — findings flow back only as
  `entra_app.tf` changes.
- If Step 1 reveals a missing SR client property → fix `entra_app.tf`, not the script.
