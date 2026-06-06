variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
}

variable "vault_token" {
  description = "Vault root token for Terraform operations"
  type        = string
  sensitive   = true
}

variable "kv_mount_path" {
  description = "Path for KV v2 secrets engine"
  type        = string
  default     = "secret"
}

variable "backstage_postgres_admin_password" {
  description = "Admin password for the Backstage PostgreSQL instance used by Vault to manage dynamic database credentials."
  type        = string
  sensitive   = true
}
