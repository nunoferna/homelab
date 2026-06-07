# Homelab

Infrastructure-as-code repository for a self-hosted Kubernetes homelab.

The repo is organized around a clear ownership model:

- Ansible prepares the host and installs k3s.
- Terraform owns cluster bootstrap and external control-plane integrations.
- Argo CD owns ongoing Kubernetes platform and application reconciliation.
- Vault is the source of truth for application secrets.

## Architecture

```text
Host bootstrap
  ansible/
    common, network, k3s, k8s_verify

Cluster bootstrap
  terraform/cluster-bootstrap
    Gateway API CRDs, Cilium, Argo CD root app

Platform GitOps
  gitops/bootstrap
    AppProjects and ApplicationSets
  gitops/platform
    Vault, External Secrets, cert-manager, observability, policy, networking resources

Apps GitOps
  gitops/apps
    Workloads such as Pi-hole

Day-two infrastructure
  terraform/aws-kms
    Vault AWS KMS auto-unseal key and credentials Secret
  terraform/vault
    Vault auth, policies, PKI, KV, database secrets
  terraform/tailscale
    Tailnet DNS and ACL policy
```

## Bootstrap Order

The intended order for a clean host is:

1. Run Ansible host bootstrap.
2. Run Terraform cluster bootstrap.
3. Let Argo CD reconcile platform resources.
4. Run Terraform AWS KMS after Vault exists in the cluster.
5. Confirm Vault is initialized, unsealed by AWS KMS, and reachable.
6. Seed required static secrets into Vault.
7. Run Terraform Vault configuration.
8. Let Argo CD reconcile applications that depend on Vault and External Secrets.

The GitHub Actions orchestrator mirrors this order when relevant files change.

## Directory Guide

| Path | Purpose |
| --- | --- |
| `ansible/` | Host packages, network hardening, k3s install, kubeconfig verification |
| `terraform/cluster-bootstrap/` | Terraform-owned Cilium and Argo CD bootstrap |
| `terraform/aws-kms/` | AWS KMS key and IAM access key for Vault auto-unseal |
| `terraform/vault/` | Vault auth methods, policies, PKI, KV, and database secrets configuration |
| `terraform/tailscale/` | Tailnet policy, DNS, and exit-node related configuration |
| `gitops/bootstrap/` | Root Argo CD AppProject and ApplicationSets |
| `gitops/platform/` | Platform services and cluster add-ons |
| `gitops/apps/` | User-facing homelab applications |
| `.github/workflows/` | Bootstrap, Terraform, and orchestration workflows |
| `scripts/pre-commit/` | Local validation helpers |

## Prerequisites

Local machine or self-hosted runner:

- `ansible`
- `terraform`
- `kubectl`
- `helm`
- `pre-commit`
- AWS credentials for `terraform/aws-kms`
- Tailscale OAuth credentials for `terraform/tailscale`
- kubeconfig access to the k3s cluster

State is currently local under `/home/nof/.terraform/...` on the runner.

## Common Commands

Run pre-commit checks:

```bash
pre-commit run --all-files
```

Run Ansible bootstrap:

```bash
ansible-playbook ansible/playbooks/k8s_bootstrap.yml
```

Validate Terraform stacks:

```bash
terraform -chdir=terraform/cluster-bootstrap init
terraform -chdir=terraform/cluster-bootstrap validate
terraform -chdir=terraform/cluster-bootstrap plan -out=tfplan

terraform -chdir=terraform/aws-kms init
terraform -chdir=terraform/aws-kms validate
terraform -chdir=terraform/aws-kms plan -out=tfplan

terraform -chdir=terraform/vault init
terraform -chdir=terraform/vault validate
terraform -chdir=terraform/vault plan -out=tfplan
```

Check key Kubernetes rollouts:

```bash
kubectl -n kube-system rollout status ds/cilium
kubectl -n argocd rollout status deploy/argocd-server
kubectl -n vault get pods
kubectl get applications -n argocd
```

## CI and Automation

The main entrypoint is `.github/workflows/orchestrator.yaml`.

Path-based routing:

- `ansible/**` runs host bootstrap.
- `terraform/cluster-bootstrap/**` and selected platform bootstrap files run cluster bootstrap.
- `terraform/aws-kms/**` runs AWS KMS provisioning.
- `terraform/vault/**` runs Vault configuration.
- `terraform/tailscale/**` runs Tailscale policy configuration.

Renovate manages dependency updates for:

- Terraform providers and modules.
- Pre-commit hooks.
- GitOps Helm chart versions.
- Terraform-owned Helm chart versions.
- Gateway API release pins.

## Secrets

Do not commit secrets.

Vault is the source of truth for application secrets. External Secrets Operator syncs Vault values into Kubernetes Secrets for workloads.

See `SECRETS.md` for required Vault paths, expected keys, and bootstrap order.

Important state note:

- `terraform/aws-kms` creates an IAM access key for Vault auto-unseal.
- The secret access key is written to Kubernetes and stored in local Terraform state.
- Keep local state files private and backed up.

## Ownership Rules

Terraform owns:

- Cilium Helm release.
- Argo CD Helm release.
- Gateway API CRD bootstrap.
- AWS KMS resources for Vault auto-unseal.
- Vault day-two configuration.
- Tailscale tailnet policy.

Argo CD owns:

- Vault Helm release.
- Platform resources under `gitops/platform`.
- Applications under `gitops/apps`.
- Cilium base resources under `gitops/platform/cilium-resources`.

Ansible owns:

- Host base setup.
- Network/firewall baseline.
- k3s installation and kubeconfig preparation.

Avoid managing the same live resource from multiple systems.

## Notes

This is a homelab, but the repo aims to follow production-style habits where they add value: clear ownership boundaries, reviewed Terraform plans, GitOps reconciliation, linting, dependency automation, and a single secret source of truth.
