output "aws_region" {
  description = "AWS region containing the Vault auto-unseal KMS key."
  value       = var.aws_region
}

output "kms_key_id" {
  description = "KMS key ID used by Vault auto-unseal."
  value       = module.vault_auto_unseal_kms.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used by Vault auto-unseal."
  value       = module.vault_auto_unseal_kms.key_arn
}

output "access_key_id" {
  description = "IAM access key ID for Vault auto-unseal."
  value       = aws_iam_access_key.vault_auto_unseal.id
}

output "secret_access_key" {
  description = "IAM secret access key for Vault auto-unseal."
  value       = aws_iam_access_key.vault_auto_unseal.secret
  sensitive   = true
}
