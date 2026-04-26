# Helper module: verifies TLS handshake on a given domain:port using openssl s_client.
# Outputs tls_valid (bool) and days_remaining (number).

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

variable "domain" {
  description = "Domain name to check TLS against."
  type        = string
}

variable "port" {
  description = "Port to connect to (e.g. 443 or 9093)."
  type        = number
}

locals {
  result_file = "/tmp/tls-check-${var.domain}-${var.port}.txt"
  days_file   = "/tmp/tls-days-${var.domain}-${var.port}.txt"
}

resource "null_resource" "tls_check" {
  triggers = {
    domain = var.domain
    port   = var.port
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      CERT_RESULT=$(echo | openssl s_client -connect "${var.domain}:${var.port}" -servername "${var.domain}" 2>/dev/null)
      if echo "$CERT_RESULT" | grep -q "Verify return code: 0 (ok)"; then
        echo "true" > "${local.result_file}"
        EXPIRY=$(echo "$CERT_RESULT" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%%s 2>/dev/null || date -j -f "%%b %%d %%T %%Y %%Z" "$EXPIRY" +%%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - $(date +%%s)) / 86400 ))
        echo "$DAYS_LEFT" > "${local.days_file}"
        echo "PASS: TLS valid on ${var.domain}:${var.port} — $DAYS_LEFT days remaining"
      else
        echo "false" > "${local.result_file}"
        echo "0" > "${local.days_file}"
        echo "FAIL: TLS verification failed on ${var.domain}:${var.port}"
        exit 1
      fi
    SHELL
  }
}

data "local_file" "tls_valid" {
  depends_on = [null_resource.tls_check]
  filename   = local.result_file
}

data "local_file" "days_remaining" {
  depends_on = [null_resource.tls_check]
  filename   = local.days_file
}

output "tls_valid" {
  description = "Whether TLS certificate is valid and trusted."
  value       = trimspace(data.local_file.tls_valid.content) == "true"
}

output "days_remaining" {
  description = "Number of days until the TLS certificate expires."
  value       = tonumber(trimspace(data.local_file.days_remaining.content))
}
