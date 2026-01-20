resource "vault_policy" "homelab_writer" {
  name   = "homelab-writer"
  policy = file("${path.module}/policies/homelab-writer.hcl")
}

resource "vault_policy" "homelab_reader" {
  name   = "homelab-reader"
  policy = file("${path.module}/policies/homelab-reader.hcl")
}
