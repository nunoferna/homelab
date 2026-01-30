terraform {
  required_version = ">= 1.14.0"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = ">= 0.25.0"
    }
  }

  backend "local" {
    path = "/home/nof/.terraform/tailscale/terraform.tfstate"
  }
}

provider "tailscale" {
  # Prefer OAuth client credentials.
  # Export these env vars (recommended for CI/secrets hygiene):
  # - TAILSCALE_OAUTH_CLIENT_ID
  # - TAILSCALE_OAUTH_CLIENT_SECRET
  # - TAILSCALE_TAILNET (optional; defaults to the tailnet owning the creds)
  #
  # Alternatively you can use TAILSCALE_API_KEY (less preferred).
}

resource "tailscale_tailnet_settings" "tailnet" {
  # Prevent manual edits in the admin console (avoids drift).
  acls_externally_managed_on = true
  acls_external_link         = var.acls_external_link
}

resource "tailscale_acl" "policy" {
  acl = file("${path.module}/policy.json")

  # First apply usually requires importing existing policy.
  # Set true only if you intentionally want to overwrite without import.
  overwrite_existing_content = var.overwrite_existing_acl
}
