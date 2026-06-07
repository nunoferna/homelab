data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "vault_auto_unseal_kms" {
  statement {
    sid = "AllowVaultAutoUnsealIamUser"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.vault_auto_unseal.arn]
    }
  }
}
