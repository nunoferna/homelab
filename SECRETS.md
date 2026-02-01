# 🔐 Secrets Management

This document outlines the **static secrets** required for the Homelab.

These values **must not** be stored in Git. The Source of Truth for all secrets in this mature DevSecOps setup is **Vault**.

## ⚠️ Order of Operations

1.  **Apply Terraform First:**
    You must run the Terraform stacks (specifically `terraform/vault`) **before** creating these secrets. Terraform configures the Vault Auth Methods, Roles, and Policies that allow applications to read these secrets.

    ```bash
    cd terraform/vault
    terraform apply
    ```

2.  **Insert Secrets into Vault:**
    Follow the guide below to insert credentials into the Vault KV (Key-Value) store.

3.  **Sync ArgoCD:**
    Once secrets are in Vault, ArgoCD applications can be safely synced.

---

## 🛠️ How to Insert Secrets into Vault

### Method 1: Vault UI (Recommended)
This is the easiest way to visualize and manage secrets.

1.  **Access:** Open [https://vault.apps.internal](https://vault.apps.internal) in your browser.
2.  **Login:**
    * **Method:** Token
    * **Token:** Use your **Root Token** (saved during the initial `vault operator init` process).
3.  **Navigate:** Click on `secret/` (KV Engine) -> **Create Secret**.
4.  **Input:**
    * **Path for Secret:** Enter the path defined in the list below (e.g., `pihole/custom-env`).
    * **Secret Data:** Add the Key and Value pairs.
5.  **Save:** Click **Save**.

### Method 2: Vault CLI (Scriptable)
Useful for bulk updates or if you are already inside the cluster.

1.  **Access Vault:**
    ```bash
    kubectl exec -ti vault-0 -n vault -- sh
    ```

2.  **Write the Secret:**
    ```bash
    # Syntax: vault kv put secret/<path> <key>=<value>
    vault kv put secret/pihole/custom-env WEBPASSWORD="my-super-secure-password"
    ```

---

## 📋 Required Secrets List

Below is the registry of all static secrets required by the applications.

### 1. Pi-hole (AdBlocking)
* **Vault Path:** `secret/pihole/custom-env`
* **Used By:** Vault Agent Injector (Sidecar)
* **Keys:**
    * `WEBPASSWORD`: The password for the Pi-hole Web Interface.

### 2. Backstage (Developer Portal)
* **Vault Path:** `secret/backstage`
* **Used By:** Backstage Backend
* **Keys:**
    * `POSTGRES_PASSWORD`: Password for the internal Postgres database.
    * `GITHUB_TOKEN`: Personal Access Token (PAT) for reading catalog files.
    * `AUTH_GITHUB_CLIENT_ID`: OAuth App Client ID.
    * `AUTH_GITHUB_CLIENT_SECRET`: OAuth App Client Secret.

### 3. Tailscale (VPN)
* **Vault Path:** `secret/tailscale`
* **Used By:** Tailscale Operator / Proxy
* **Keys:**
    * `TS_AUTHKEY`: Ephemeral/Reusable auth key from [Tailscale Admin Panel](https://login.tailscale.com/admin/settings/keys).

### 4. Cert-Manager (DNS Challenges)
* **Vault Path:** `secret/cert-manager/cloudflare`
* **Used By:** Cert-Manager (DNS-01 Issuer)
* **Keys:**
    * `api-token`: Cloudflare API Token (Edit Zone DNS permissions).
* *Note: Only required if using Let's Encrypt DNS-01 validation.*

### 5. Loki (Object Storage)
* **Vault Path:** `secret/observability/loki`
* **Used By:** Loki (S3 Storage)
* **Keys:**
    * `access_key_id`: AWS/Minio Access Key.
    * `secret_access_key`: AWS/Minio Secret Key.