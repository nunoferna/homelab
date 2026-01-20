# Kubernetes Auth
resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  description = "Kubernetes authentication for in-cluster workloads"
}

resource "vault_kubernetes_auth_backend_config" "k8s" {
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt = false
}

resource "vault_kubernetes_auth_backend_role" "default" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "default"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["*"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.homelab_reader.name]
}

# AppRole Auth
resource "vault_auth_backend" "approle" {
  type        = "approle"
  description = "AppRole authentication for CI/CD pipelines"
}

resource "vault_approle_auth_backend_role" "homelab_ci" {
  backend        = vault_auth_backend.approle.path
  role_name      = "homelab-ci"
  token_policies = [vault_policy.homelab_writer.name]
  token_ttl      = var.approle_token_ttl
  token_max_ttl  = var.approle_token_max_ttl

  secret_id_bound_cidrs = ["0.0.0.0/0"]
  token_bound_cidrs     = ["0.0.0.0/0"]
}
