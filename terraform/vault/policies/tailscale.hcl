path "secret/data/tailscale/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/tailscale/*" {
  capabilities = ["read", "list"]
}
