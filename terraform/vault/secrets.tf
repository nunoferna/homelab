resource "vault_mount" "kv" {
  path        = var.kv_mount_path
  type        = "kv-v2"
  description = "KV v2 secrets engine for homelab"
  
  options = {
    version = "2"
  }
}
