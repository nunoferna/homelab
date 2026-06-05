# AWS KMS

This stack creates the AWS KMS key and IAM credentials used by Vault auto-unseal.

This stack also writes the `vault-awskms-credentials` Kubernetes Secret before Argo CD reconciles the Vault Helm app.

Environment-specific, non-secret values live in `terraform.tfvars`.

The generated IAM secret access key is sensitive and stored in Terraform state. Keep `/home/nof/.terraform/aws-kms/terraform.tfstate` private.
