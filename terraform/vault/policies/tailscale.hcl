path "secret/data/tailscale/*" {
  capabilities = ["read"]
}

path "secret/metadata/tailscale/*" {
  capabilities = ["read", "list"]
}
