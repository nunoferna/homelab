output "kv_mount_path" {
  description = "Path where KV v2 secrets engine is mounted"
  value       = vault_mount.kv.path
}

output "kubernetes_auth_path" {
  description = "Path for Kubernetes authentication"
  value       = vault_auth_backend.kubernetes.path
}

output "approle_auth_path" {
  description = "Path for AppRole authentication"
  value       = vault_auth_backend.approle.path
}

output "approle_role_id" {
  description = "Role ID for homelab-ci AppRole"
  value       = vault_approle_auth_backend_role.homelab_ci.role_id
  sensitive   = true
}

output "pki_mount_path" {
  description = "Path where PKI secrets engine is mounted"
  value       = vault_mount.pki.path
}

output "pki_root_ca_certificate" {
  description = "Root CA certificate"
  value       = vault_pki_secret_backend_root_cert.root.certificate
  sensitive   = false
}

output "pki_issuing_ca_url" {
  description = "Issuing CA URL"
  value       = vault_pki_secret_backend_config_urls.config_urls.issuing_certificates[0]
}
