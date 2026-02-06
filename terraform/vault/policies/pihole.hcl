path "secret/data/pihole/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/pihole/*" {
  capabilities = ["read", "list"]
}
