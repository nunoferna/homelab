provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

module "vault_auto_unseal_kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 4.2"

  description             = "Vault auto-unseal key for homelab"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  aliases                 = ["${var.name_prefix}-auto-unseal"]
  key_administrators      = [data.aws_caller_identity.current.arn]
  source_policy_documents = [data.aws_iam_policy_document.vault_auto_unseal_kms.json]

  tags = {
    Name      = "${var.name_prefix}-auto-unseal"
    ManagedBy = "terraform"
    Service   = "vault"
  }
}

resource "aws_iam_user" "vault_auto_unseal" {
  name          = "${var.name_prefix}-auto-unseal"
  force_destroy = false

  tags = {
    ManagedBy = "terraform"
    Service   = "vault"
  }
}

resource "aws_iam_access_key" "vault_auto_unseal" {
  user = aws_iam_user.vault_auto_unseal.name
}

resource "kubernetes_secret" "vault_awskms_credentials" {
  metadata {
    name      = "vault-awskms-credentials"
    namespace = var.vault_namespace
  }

  data = {
    AWS_ACCESS_KEY_ID        = aws_iam_access_key.vault_auto_unseal.id
    AWS_SECRET_ACCESS_KEY    = aws_iam_access_key.vault_auto_unseal.secret
    AWS_REGION               = var.aws_region
    VAULT_AWSKMS_SEAL_KEY_ID = module.vault_auto_unseal_kms.key_id
    VAULT_SEAL_TYPE          = "awskms"
  }

  type = "Opaque"
}
