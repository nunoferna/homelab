resource "vault_policy" "cert_manager" {
  name   = "cert-manager"
  policy = file("${path.module}/policies/cert-manager.hcl")
}

resource "vault_policy" "backstage" {
  name   = "backstage"
  policy = file("${path.module}/policies/backstage.hcl")
}

resource "vault_policy" "tailscale" {
  name   = "tailscale"
  policy = file("${path.module}/policies/tailscale.hcl")
}

resource "vault_policy" "pihole" {
  name   = "pihole"
  policy = file("${path.module}/policies/pihole.hcl")
}
