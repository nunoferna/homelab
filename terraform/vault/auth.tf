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

# cert-manager Kubernetes Auth Role
resource "vault_kubernetes_auth_backend_role" "cert_manager" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cert-manager"
  bound_service_account_names      = ["cert-manager"]
  bound_service_account_namespaces = ["cert-manager"]
  token_ttl                        = 86400 # 24 hours
  token_policies                   = [vault_policy.cert_manager.name]
}

resource "vault_kubernetes_auth_backend_role" "backstage" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "backstage"
  bound_service_account_names      = ["backstage"]
  bound_service_account_namespaces = ["backstage"]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.backstage.name]
}
