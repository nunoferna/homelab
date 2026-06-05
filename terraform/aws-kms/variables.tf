variable "aws_region" {
  description = "AWS region for the Vault auto-unseal KMS key."
  type        = string
}

variable "name_prefix" {
  description = "Name prefix for Vault auto-unseal AWS resources."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig used to create the Vault AWS KMS credentials Secret."
  type        = string
  default     = "~/.kube/config"
}

variable "vault_namespace" {
  description = "Namespace where Vault is installed."
  type        = string
  default     = "vault"
}
