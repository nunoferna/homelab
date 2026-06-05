# Cluster Bootstrap

Terraform owns the bootstrap releases for Cilium and Argo CD.

Argo CD owns Vault and Kubernetes resources that are not part of the bootstrap Helm releases, including `gitops/security/vault`, `gitops/networking/cilium-resources`, and `gitops/security/vault-resources`.

Vault AWS KMS auto-unseal resources live in `terraform/aws-kms`.

Environment-specific, non-secret values live in `terraform.tfvars`.

Helm values for Terraform-owned releases live in `values/`:

- `values/cilium.yaml`
- `values/argocd.yaml`

Version pins live where they are consumed:

- Helm chart versions are literal `helm_release.version` values in `main.tf`. Renovate updates them through its Terraform manager.
- The Gateway API release pin is a local value in `main.tf`. Renovate updates it through the regex manager in `renovate.json`.

This keeps a clean clone simple: no synthetic Helm chart, no generated chart lock, and no version indirection.
