path "secret/data/pihole/*" {
  capabilities = ["read"]
}

path "secret/metadata/pihole/*" {
  capabilities = ["read", "list"]
}
