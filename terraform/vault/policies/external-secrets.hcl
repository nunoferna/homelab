# Pihole credentials
path "secret/data/pihole/*" {
  capabilities = ["read", "list"]
}

# Tailscale credentials
path "secret/data/tailscale/*" {
  capabilities = ["read", "list"]
}

# Backstage GitHub secrets
path "secret/data/backstage/*" {
  capabilities = ["read", "list"]
}

# KV v2 metadata access
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# Backstage dynamic database credentials
path "database/creds/backstage-role" {
  capabilities = ["read"]
}
