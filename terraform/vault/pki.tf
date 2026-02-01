# Enable PKI Secrets Engine
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "PKI secrets engine for homelab certificates"
  default_lease_ttl_seconds = 315360000 # 10 years
  max_lease_ttl_seconds     = 315360000 # 10 years
}

# Generate Root CA
resource "vault_pki_secret_backend_root_cert" "root" {
  backend              = vault_mount.pki.path
  type                 = "internal"
  common_name          = "Root CA"
  ttl                  = "315360000" # 10 years
  format               = "pem"
  private_key_format   = "der"
  key_type             = "rsa"
  key_bits             = 4096
  exclude_cn_from_sans = true
  ou                   = "Infrastructure"
  organization         = "Homelab"
  issuer_name          = "root-ca"
}

# Configure PKI URLs
resource "vault_pki_secret_backend_config_urls" "config_urls" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["http://vault.vault.svc:8200/v1/pki/ca"]
  crl_distribution_points = ["http://vault.vault.svc:8200/v1/pki/crl"]
}

# Create PKI Role for *.apps.internal
resource "vault_pki_secret_backend_role" "domain" {
  backend               = vault_mount.pki.path
  name                  = "domain"
  ttl                   = 7776000 # 90 days
  max_ttl               = 7776000 # 90 days
  allow_ip_sans         = true
  key_type              = "rsa"
  key_bits              = 2048
  allowed_domains       = ["apps.internal"]
  allow_subdomains      = true
  allow_glob_domains    = true
  allow_any_name        = false
  enforce_hostnames     = true
  allow_localhost       = false
  require_cn            = false
  use_csr_common_name   = true
  use_csr_sans          = true
  server_flag           = true
  client_flag           = true
  code_signing_flag     = false
  email_protection_flag = false
  key_usage             = ["DigitalSignature", "KeyAgreement", "KeyEncipherment"]
  ext_key_usage         = ["ServerAuth", "ClientAuth"]
}
