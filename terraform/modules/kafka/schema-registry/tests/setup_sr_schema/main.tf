# Helper module: POST a schema to Apicurio via Confluent-compatible API and read it back.
# Subject name follows Confluent naming standard: <topic>-value or <topic>-key.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
}

variable "ccompat_url" {
  description = "Confluent-compatible Schema Registry base URL (e.g. http://host:8080/apis/ccompat/v7)."
  type        = string
}

variable "subject" {
  description = "Subject name following Confluent naming standard (<topic>-value)."
  type        = string
}

variable "schema" {
  description = "JSON-encoded JSON schema string."
  type        = string
}

locals {
  schema_file  = "/tmp/sr-inttest-schema-${replace(var.subject, "/", "-")}.json"
  id_file      = "/tmp/sr-inttest-id-${replace(var.subject, "/", "-")}.txt"
  list_file    = "/tmp/sr-inttest-subjects-${replace(var.subject, "/", "-")}.txt"
}

# Wait for Apicurio to be healthy before posting
resource "null_resource" "wait_healthy" {
  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      echo "Waiting for Apicurio health at ${var.ccompat_url}..."
      for i in $(seq 1 30); do
        STATUS=$(curl -s -o /dev/null -w "%%{http_code}" "${var.ccompat_url}/subjects" || true)
        if [ "$STATUS" = "200" ]; then
          echo "Apicurio is healthy (HTTP 200)"
          exit 0
        fi
        echo "  attempt $i: HTTP $STATUS — retrying in 5s..."
        sleep 5
      done
      echo "ERROR: Apicurio did not become healthy within 150s"
      exit 1
    SHELL
  }
}

# POST schema and capture the returned schema ID
resource "null_resource" "post_schema" {
  depends_on = [null_resource.wait_healthy]

  triggers = {
    subject = var.subject
    schema  = var.schema
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      PAYLOAD=$(printf '{"schema": %s, "schemaType": "JSON"}' "$(echo '${var.schema}' | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')")
      RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        -d "$PAYLOAD" \
        "${var.ccompat_url}/subjects/${var.subject}/versions")
      echo "$RESPONSE"
      echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])" > "${local.id_file}"
      echo "Schema registered with ID: $(cat ${local.id_file})"
    SHELL
  }
}

# GET /subjects and verify the subject is listed
resource "null_resource" "list_subjects" {
  depends_on = [null_resource.post_schema]

  triggers = {
    subject = var.subject
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      SUBJECTS=$(curl -s "${var.ccompat_url}/subjects")
      echo "$SUBJECTS"
      if echo "$SUBJECTS" | python3 -c "import sys,json; subjects=json.load(sys.stdin); exit(0 if '${var.subject}' in subjects else 1)"; then
        echo "true" > "${local.list_file}"
        echo "PASS: subject '${var.subject}' found in registry"
      else
        echo "false" > "${local.list_file}"
        echo "FAIL: subject '${var.subject}' not found in registry"
        exit 1
      fi
    SHELL
  }
}

data "local_file" "schema_id" {
  depends_on = [null_resource.post_schema]
  filename   = local.id_file
}

data "local_file" "subject_exists" {
  depends_on = [null_resource.list_subjects]
  filename   = local.list_file
}

output "schema_id" {
  description = "Schema ID returned by the registry after POST."
  value       = tonumber(trimspace(data.local_file.schema_id.content))
}

output "subject_exists" {
  description = "Whether the subject appears in GET /subjects."
  value       = trimspace(data.local_file.subject_exists.content) == "true"
}
