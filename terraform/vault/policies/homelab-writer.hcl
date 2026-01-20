# Full access to secret data
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage secret metadata
path "secret/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Delete versions
path "secret/delete/*" {
  capabilities = ["update"]
}

# Undelete versions
path "secret/undelete/*" {
  capabilities = ["update"]
}

# Destroy versions
path "secret/destroy/*" {
  capabilities = ["update"]
}
