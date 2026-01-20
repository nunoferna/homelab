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

variable "approle_token_ttl" {
  description = "TTL for AppRole tokens in seconds"
  type        = number
  default     = 3600
}

variable "approle_token_max_ttl" {
  description = "Maximum TTL for AppRole tokens in seconds"
  type        = number
  default     = 86400
}
