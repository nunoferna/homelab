# Read-only access to secret data
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Read secret metadata
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
