resource "vault_policy" "homelab_writer" {
  name   = "homelab-writer"
  policy = file("${path.module}/policies/homelab-writer.hcl")
}

resource "vault_policy" "homelab_reader" {
  name   = "homelab-reader"
  policy = file("${path.module}/policies/homelab-reader.hcl")
}

resource "vault_policy" "cert_manager" {
  name   = "cert-manager"
  policy = file("${path.module}/policies/cert-manager.hcl")
}
