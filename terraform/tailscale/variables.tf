variable "acls_external_link" {
  description = "URL shown in Tailscale admin as the external ACL management link."
  type        = string
  default     = "https://github.com/nunoferna/homelab"
}

variable "overwrite_existing_acl" {
  description = "If true, allows overwriting the existing policy without importing it first. Use with care."
  type        = bool
  default     = false
}
