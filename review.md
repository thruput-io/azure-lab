# Terraform Module Review — module-refactor

## ✅ What's Good

| Area                   | Finding                                                                                                          |
|------------------------|------------------------------------------------------------------------------------------------------------------|
| Module structure       | Follows HashiCorp standard layout (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `tests/`)            |
| Test coverage          | Unit tests with mock providers for all modules; integration tests for all submodules; e2e test for kafka parent  |
| `for_each` on topics   | Correct use of `for_each` instead of `count` — safe for topic additions/removals                                 |
| Sensitive outputs      | `client_secret`, `go_client_json`, `java_client_properties` all marked `sensitive = true`                        |
| Private endpoint + DNS | Correctly wired: private endpoint → DNS A record → VNet link                                                     |
| RBAC-only Key Vault    | `rbac_authorization_enabled = true`, no legacy access policies                                                   |
| Conditional cert       | `azurerm_key_vault_certificate` uses `count = (var.pfx_base64 != null ...) ? 1 : 0`                              |
| Client config content  | `go-client.json` matches `oauth.json` keys exactly; `java-client.properties` uses correct Kafka 4.0 renamed keys |

---

## ❌ Issues Found

### 1. `required_version` missing from all modules — HIGH

Every `providers.tf` only has `required_providers` but no `required_version`. The module will silently accept any Terraform version, including ones that don't support the testing framework (< 1.6).

**Fix — add to every `providers.tf`:**
```hcl
terraform {
  required_version = ">= 1.6"
  required_providers { ... }
}
```

Affected files:
- `terraform/modules/keyvault/providers.tf`
- `terraform/modules/kafka/providers.tf`
- `terraform/modules/kafka/eventhub/providers.tf`
- `terraform/modules/kafka/schema-registry/providers.tf`
- `terraform/modules/kafka/app-gateway/providers.tf`

---

### 2. `schema-registry` module still uses ACR admin credentials — HIGH

`schema-registry/main.tf` uses `var.acr_username` / `var.acr_password` (admin credentials). The architectural decision was to disable ACR admin and use managed identity. This contradicts that decision and keeps a security weakness.

**Fix:** Remove `image_registry_credential` block, add `identity { type = "SystemAssigned" }` to the container group, and add an `AcrPull` role assignment output.

Affected files:
- `terraform/modules/kafka/schema-registry/main.tf`
- `terraform/modules/kafka/schema-registry/variables.tf`
- `terraform/modules/kafka/schema-registry/tests/unit.tftest.hcl`
- `terraform/modules/kafka/schema-registry/tests/integration.tftest.hcl`
- `terraform/modules/kafka/schema-registry/tests/setup_sr/main.tf`

---

### 3. No variable validation rules — MEDIUM

None of the variables have `validation` blocks. Critical inputs like `partition_count`, `message_retention`, `namespace_name` length, and `token_endpoint_url` format have no guards.

**Example fix for eventhub `namespace_name`:**
```hcl
variable "namespace_name" {
  type = string
  validation {
    condition     = length(var.namespace_name) <= 50 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.namespace_name))
    error_message = "namespace_name must start with a letter, contain only alphanumerics/hyphens, max 50 chars."
  }
}
```

---

### 4. `keyvault` SKU hardcoded to `"standard"` — LOW

`sku_name = "standard"` is hardcoded in `keyvault/main.tf`. Should be a variable with `"standard"` as default to allow Premium KV if needed.

---

### 5. `topics` variable has hardcoded defaults — LOW

`eventhub/variables.tf` defaults `topics` to `orders.placed` / `checks.kafka`. A reusable module should default to `{}` (empty map) and let the caller define topics.

---

### 6. Root `acr.tf` still has `admin_enabled = true` — LOW (pre-existing)

`terraform/acr.tf` still has `admin_enabled = true` which was flagged for removal. Not introduced by this PR but worth tracking.

---

## Summary

| # | Issue | Severity | File(s) |
|---|---|---|---|
| 1 | ~~`required_version` missing~~ | ~~HIGH~~ | ✅ Fixed in PR 1 |
| 2 | ~~ACR admin creds in schema-registry~~ | ~~HIGH~~ | ✅ Fixed in PR 2 |
| 3 | ~~No variable validation~~ | ~~MEDIUM~~ | ✅ Fixed in PR 1 |
| 4 | ~~KV SKU hardcoded~~ | ~~LOW~~ | ✅ Fixed in PR 1 |
| 5 | ~~Topics default not empty~~ | ~~LOW~~ | ✅ Fixed in PR 1 |
| 6 | ~~Root ACR admin enabled~~ | ~~LOW~~ | ✅ Fixed in PR 2 |

**Recommendation:** Fix issues 1 and 2 before using these modules in production. Issues 3–5 are quality improvements.

---

## Fix Plan

### PR 1 — `fix/review-issues` ✅ Merged to main

| # | Fix                                                                                                                    | Severity |
|---|------------------------------------------------------------------------------------------------------------------------|----------|
| 1 | Add `required_version = ">= 1.6"` to all 5 `providers.tf`                                                              | HIGH     |
| 3 | Add variable validation rules (`namespace_name`, `partition_count`, `message_retention`, `name`, `token_endpoint_url`) | MEDIUM   |
| 4 | Make Key Vault SKU a variable (default `"standard"`)                                                                   | LOW      |
| 5 | Change `topics` default to `{}`                                                                                        | LOW      |

### PR 2 — `fix/schema-registry-managed-identity` ✅ Merged to main

| # | Fix                                                                                                                | Severity |
|---|--------------------------------------------------------------------------------------------------------------------|----------|
| 2 | Remove ACR admin credentials from `schema-registry` module, use `SystemAssigned` managed identity + `AcrPull` role | HIGH     |
| 6 | Disable `admin_enabled` in root `terraform/acr.tf` + update root `apicurio.tf` to use managed identity             | LOW      |

Issues 2 and 6 are grouped: both are the same architectural change (ACR admin → managed identity) and must land together.
