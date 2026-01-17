#!/bin/bash
set -euo pipefail

echo "This script is deprecated."
echo "Use:"
echo "- ./bootstrap/vault/init-and-configure.sh   (one-time, local)"
echo "- ./bootstrap/vault/push-secrets.sh         (CI, uses AppRole)"
exit 1

VAULT_NS="vault"
VAULT_POD="vault-0"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then

  # In-cluster TLS material is mounted from the vault-server-tls secret.
  # cert-manager secrets typically contain tls.crt, tls.key, and (sometimes) ca.crt.
  echo "VAULT_TOKEN is not set. Export VAULT_TOKEN (root token) and re-run."
  exit 1
fi

echo "--- [Vault] Waiting for pod ${VAULT_NS}/${VAULT_POD} ---"
kubectl -n "${VAULT_NS}" wait --for=condition=Ready pod "${VAULT_POD}" --timeout=10m

vault_cli_env() {
  cat <<EOF
export VAULT_ADDR=https://127.0.0.1:8200;
if [ -s "${VAULT_CACERT_IN_POD}" ]; then
  export VAULT_CACERT="${VAULT_CACERT_IN_POD}";
else
  export VAULT_SKIP_VERIFY=true;
fi
EOF
}
vault_exec() {
  kubectl -n "${VAULT_NS}" exec -i "${VAULT_POD}" -- /bin/sh -lc "$*"
}

echo "--- [Vault] Checking status ---"
# The vault binary is available in the pod.
vault_exec "$(vault_cli_env); vault status" >/dev/null

echo "--- [Vault] Enabling KV v2 at path 'secret' (if missing) ---"
vault_exec "$(vault_cli_env); export VAULT_TOKEN='${VAULT_TOKEN}'; vault secrets list -format=json | grep -q '\"secret/\"' || vault secrets enable -path=secret kv-v2" >/dev/null

echo "--- [Vault] Writing Pi-hole admin password ---"
PIHOLE_PASSWORD="$(openssl rand -base64 24)"
vault_exec "$(vault_cli_env); export VAULT_TOKEN='${VAULT_TOKEN}'; vault kv put secret/homelab/pihole password='${PIHOLE_PASSWORD}'" >/dev/null

echo "Pi-hole password written to Vault at secret/homelab/pihole (key: password)"

if [ -n "${TAILSCALE_CLIENT_ID:-}" ] && [ -n "${TAILSCALE_CLIENT_SECRET:-}" ]; then
  echo "--- [Vault] Writing Tailscale OAuth creds ---"
  vault_exec "$(vault_cli_env); export VAULT_TOKEN='${VAULT_TOKEN}'; vault kv put secret/homelab/tailscale client_id='${TAILSCALE_CLIENT_ID}' client_secret='${TAILSCALE_CLIENT_SECRET}'" >/dev/null
  echo "Tailscale creds written to Vault at secret/homelab/tailscale (client_id/client_secret)"
else
  echo "Skipping Tailscale creds: set TAILSCALE_CLIENT_ID and TAILSCALE_CLIENT_SECRET to write them."
fi

echo "--- [Vault] Creating limited policy/token for External Secrets Operator ---"
POLICY_NAME="external-secrets-read"
POLICY_FILE="/tmp/${POLICY_NAME}.hcl"

# Write policy file inside the pod.
vault_exec "cat > ${POLICY_FILE} <<'EOF'
path \"secret/data/homelab/*\" {
  capabilities = [\"read\"]
}

path \"secret/metadata/homelab/*\" {
  capabilities = [\"list\", \"read\"]
}
EOF" >/dev/null

vault_exec "$(vault_cli_env); export VAULT_TOKEN='${VAULT_TOKEN}'; vault policy write ${POLICY_NAME} ${POLICY_FILE}" >/dev/null

# Create a token and capture it.
ESO_TOKEN="$(vault_exec "$(vault_cli_env); export VAULT_TOKEN='${VAULT_TOKEN}'; vault token create -policy=${POLICY_NAME} -format=json" | awk -F'"' '/"client_token"/{print $4; exit}')"

if [ -z "${ESO_TOKEN}" ]; then
  echo "Failed to create ESO token"
  exit 1
fi

echo "--- [K8s] Creating token secret for External Secrets Operator ---"
kubectl get ns external-secrets >/dev/null 2>&1 || kubectl create ns external-secrets

kubectl -n external-secrets delete secret vault-token >/dev/null 2>&1 || true
kubectl -n external-secrets create secret generic vault-token --from-literal=vault-token="${ESO_TOKEN}" >/dev/null

echo "--- Done ---"
echo "- Vault KV secrets written under secret/homelab/*"
echo "- K8s Secret external-secrets/vault-token created (used by ClusterSecretStore vault)"
echo "- Pi-hole password generated and stored in Vault (not printed)"
