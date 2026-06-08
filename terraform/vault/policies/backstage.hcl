# Read dynamic database credentials
path "database/creds/backstage-role" {
  capabilities = ["read"]
}

# Optional: Read static secrets
path "secret/data/backstage/*" {
  capabilities = ["read"]
}

path "secret/metadata/backstage/*" {
  capabilities = ["read", "list"]
}
