variable "kubeconfig_path" {
  description = "Path to the kubeconfig used by Terraform, kubectl, and Helm."
  type        = string
  default     = "~/.kube/config"
}

variable "repo_url" {
  description = "Git repository used by the root Argo CD application."
  type        = string
}

variable "repo_revision" {
  description = "Git revision used by the root Argo CD application."
  type        = string
  default     = "main"
}

variable "cilium_k8s_service_host" {
  description = "Kubernetes API host Cilium should use."
  type        = string
}

variable "cilium_k8s_service_port" {
  description = "Kubernetes API port Cilium should use."
  type        = string
  default     = "6443"
}
