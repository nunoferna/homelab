# Enable database secrets engine
resource "vault_mount" "database" {
  path = "database"
  type = "database"
}

# Configure PostgreSQL connection
resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.database.path
  name          = "backstage-postgres"
  allowed_roles = ["backstage-role"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@backstage-postgresql.backstage.svc:5432/backstage?sslmode=disable"
    username       = "postgres"
    password       = "rootpassword123"
  }

  verify_connection = false # Set true after PostgreSQL is running
}

# Create role for dynamic credentials
resource "vault_database_secret_backend_role" "backstage" {
  backend = vault_mount.database.path
  name    = "backstage-role"
  db_name = vault_database_secret_backend_connection.postgres.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT ALL PRIVILEGES ON DATABASE backstage TO \"{{name}}\";",
    "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";"
  ]
  revocation_statements = [
    "DROP ROLE IF EXISTS \"{{name}}\";"
  ]
  default_ttl = 3600  # 1 hour (matches docs)
  max_ttl     = 86400 # 24 hours (matches docs)
}
