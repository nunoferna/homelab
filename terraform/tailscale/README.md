# Tailscale Policy (Terraform)

This folder manages your tailnet policy via the Tailscale Terraform provider.

It:
- Sets `acls_externally_managed_on = true` (prevents console edits/drift)
- Applies a full policy file (JSON) from `policy.json`
- Enables auto-approval for exit nodes tagged `tag:k8s`

## Prereqs

- Terraform installed
- Tailscale API auth configured via env vars (recommended):
  - `TAILSCALE_OAUTH_CLIENT_ID`
  - `TAILSCALE_OAUTH_CLIENT_SECRET`
  - optionally `TAILSCALE_TAILNET`

(You can also use `TAILSCALE_API_KEY`, but OAuth is preferred.)

## First apply (import existing policy)

The `tailscale_acl` resource replaces the **entire** policy file.
To avoid accidentally overwriting what’s already in your tailnet, import first:

- `terraform init`
- `terraform import tailscale_acl.policy acl`
- `terraform plan`
- `terraform apply`

If you intentionally want to overwrite without import, set:

- `-var='overwrite_existing_acl=true'`

## Notes for Kubernetes exit node

Your Connector defaults to tag `tag:k8s`.
With the policy in `policy.json`, exit-node approvals for `tag:k8s` are automatic.

If the operator cannot tag devices, you’ll need to adjust `tagOwners` to allow the operator’s OAuth identity to use the tag.
