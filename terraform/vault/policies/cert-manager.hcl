# Allow cert-manager to sign and issue certificates
path "pki/sign/homelab-dot-home-dot-lab" {
  capabilities = ["create", "update"]
}

path "pki/issue/homelab-dot-home-dot-lab" {
  capabilities = ["create"]
}

# Allow reading PKI configuration
path "pki/config/urls" {
  capabilities = ["read"]
}

path "pki/ca" {
  capabilities = ["read"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}
