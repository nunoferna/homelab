provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

resource "aws_kms_key" "vault_auto_unseal" {
  description             = "Vault auto-unseal key for homelab"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name      = "${var.name_prefix}-auto-unseal"
    ManagedBy = "terraform"
    Service   = "vault"
  }
}

resource "aws_kms_alias" "vault_auto_unseal" {
  name          = "alias/${var.name_prefix}-auto-unseal"
  target_key_id = aws_kms_key.vault_auto_unseal.key_id
}

resource "aws_iam_user" "vault_auto_unseal" {
  name = "${var.name_prefix}-auto-unseal"

  tags = {
    ManagedBy = "terraform"
    Service   = "vault"
  }
}

data "aws_iam_policy_document" "vault_auto_unseal" {
  statement {
    sid = "VaultAutoUnsealKmsAccess"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
    ]

    resources = [aws_kms_key.vault_auto_unseal.arn]
  }
}

resource "aws_iam_user_policy" "vault_auto_unseal" {
  name   = "${var.name_prefix}-auto-unseal"
  user   = aws_iam_user.vault_auto_unseal.name
  policy = data.aws_iam_policy_document.vault_auto_unseal.json
}

resource "aws_iam_access_key" "vault_auto_unseal" {
  user = aws_iam_user.vault_auto_unseal.name
}

resource "kubernetes_namespace" "vault" {
  metadata {
    name = var.vault_namespace
  }
}

resource "kubernetes_secret" "vault_awskms_credentials" {
  metadata {
    name      = "vault-awskms-credentials"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID        = aws_iam_access_key.vault_auto_unseal.id
    AWS_SECRET_ACCESS_KEY    = aws_iam_access_key.vault_auto_unseal.secret
    AWS_REGION               = var.aws_region
    VAULT_AWSKMS_SEAL_KEY_ID = aws_kms_key.vault_auto_unseal.key_id
    VAULT_SEAL_TYPE          = "awskms"
  }

  type = "Opaque"
}
