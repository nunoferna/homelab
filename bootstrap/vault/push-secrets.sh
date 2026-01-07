#!/bin/bash
set -euo pipefail

# Never allow command tracing here; it would leak secrets to logs.
set +x

# Pushes runtime secrets into Vault using AppRole (intended for CI/self-hosted runner).
# Writes:
# - secret/homelab/tailscale (client_id, client_secret) if env vars are set
# - secret/homelab/pihole (password) only if it does not exist yet

VAULT_NS="vault"
VAULT_POD="vault-0"

KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-5s}"

STATE_DIR="${STATE_DIR:-$HOME/.homelab/vault}"
CREDS_FILE="${CREDS_FILE:-$STATE_DIR/vault-approle.json}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if [ -z "${VAULT_APPROLE_ROLE_ID:-}" ] || [ -z "${VAULT_APPROLE_SECRET_ID:-}" ]; then
  if [ -f "${CREDS_FILE}" ]; then
    VAULT_APPROLE_ROLE_ID="$(grep -o '"role_id"\s*:\s*"[^"]*"' "${CREDS_FILE}" | head -n1 | awk -F'"' '{print $4}')"
    VAULT_APPROLE_SECRET_ID="$(grep -o '"secret_id"\s*:\s*"[^"]*"' "${CREDS_FILE}" | head -n1 | awk -F'"' '{print $4}')"
    export VAULT_APPROLE_ROLE_ID VAULT_APPROLE_SECRET_ID
  fi
fi

if [ -z "${VAULT_APPROLE_ROLE_ID:-}" ] || [ -z "${VAULT_APPROLE_SECRET_ID:-}" ]; then
  echo "VAULT_APPROLE_ROLE_ID / VAULT_APPROLE_SECRET_ID must be set (or present in ${CREDS_FILE})"
  exit 1
fi

vault_exec() {
  kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" exec -i "${VAULT_POD}" -- /bin/sh -lc "$*"
}

vault_exec_no_stdin() {
  kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" exec "${VAULT_POD}" -- /bin/sh -lc "$*"
}

dump_vault_debug() {
  echo
  echo "--- [Vault][Debug] Namespace resources ---"
  kubectl -n "${VAULT_NS}" get pods -o wide 2>/dev/null || true
  kubectl -n "${VAULT_NS}" get statefulset,svc,pvc -o wide 2>/dev/null || true

  if kubectl -n "${VAULT_NS}" get pod "${VAULT_POD}" --request-timeout="${KUBECTL_TIMEOUT}" >/dev/null 2>&1; then
    echo
    echo "--- [Vault][Debug] Pod describe (${VAULT_NS}/${VAULT_POD}) ---"
    kubectl -n "${VAULT_NS}" describe pod "${VAULT_POD}" 2>/dev/null || true
    echo
    echo "--- [Vault][Debug] Pod logs (last 200 lines) ---"
    kubectl -n "${VAULT_NS}" logs "${VAULT_POD}" --all-containers --tail=200 2>/dev/null || true
  fi

  echo
  echo "--- [Vault][Debug] Recent events (${VAULT_NS}) ---"
  kubectl -n "${VAULT_NS}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 50 || true
  echo
}

ensure_vault_pod() {
  local deadline
  deadline=$((SECONDS + 600))

  # NOTE: Vault's readinessProbe runs `vault status` and fails while sealed/uninitialized.
  # Waiting for condition=Ready would deadlock this script.
  echo "--- [Vault] Waiting for pod ${VAULT_NS}/${VAULT_POD} to be Running ---"
  until kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" get pod "${VAULT_POD}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q '^Running$'; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: Timed out waiting for ${VAULT_NS}/${VAULT_POD} to be Running."
      dump_vault_debug
      exit 1
    fi
    sleep 2
  done

  echo "--- [Vault] Waiting for vault process to accept exec ---"
  until vault_exec_no_stdin "export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json 2>/dev/null || true" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: Timed out waiting for Vault to respond to 'vault status'."
      dump_vault_debug
      exit 1
    fi
    sleep 2
  done
}

ensure_vault_pod
echo "--- [Vault] Checking init/seal status ---"
STATUS_JSON="$(vault_exec_no_stdin "export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json 2>/dev/null || true" 2>/dev/null || true)"

if ! echo "${STATUS_JSON}" | grep -q '"initialized"\s*:\s*true'; then
  echo "Vault is not initialized yet. Run ./bootstrap/vault/init-and-configure.sh once locally."
  exit 1
fi

if echo "${STATUS_JSON}" | grep -q '"sealed"\s*:\s*true'; then
  echo "Vault is sealed. Ensure the workflow unseal step ran (VAULT_UNSEAL_KEY set)."
  exit 1
fi

echo "--- [Vault] Logging in via AppRole ---"
# IMPORTANT: Do not use `vault auth list` here. It requires a privileged token.
# The only thing we can/should do in CI is attempt an AppRole login and handle errors.
LOGIN_OUT="$(vault_exec_no_stdin "export VAULT_ADDR=http://127.0.0.1:8200; vault write -format=json auth/approle/login role_id='${VAULT_APPROLE_ROLE_ID}' secret_id='${VAULT_APPROLE_SECRET_ID}' 2>&1" || true)"
VAULT_TOKEN="$(printf '%s' "${LOGIN_OUT}" | awk -F'"' '/"client_token"/{print $4; exit}' || true)"

if [ -z "${VAULT_TOKEN}" ]; then
  if printf '%s' "${LOGIN_OUT}" | grep -qiE 'no handler for route|unsupported path|permission denied|404'; then
    echo "Failed to login via AppRole. This usually means AppRole auth is not enabled/configured in Vault yet."
    echo "Run ./bootstrap/vault/init-and-configure.sh once on the runner/Pi to enable AppRole and generate ${CREDS_FILE}."
  else
    echo "Failed to login to Vault via AppRole. Verify VAULT_APPROLE_ROLE_ID/VAULT_APPROLE_SECRET_ID (or ${CREDS_FILE})."
  fi
  echo "Vault login output (sanitized):"
  echo "${LOGIN_OUT}" | head -n 5
  exit 1
fi

# Ensure Pi-hole password exists once.
if ! vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault kv get -format=json secret/homelab/pihole" >/dev/null 2>&1; then
  PIHOLE_PASSWORD="$(openssl rand -base64 24)"
  vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault kv put secret/homelab/pihole password='${PIHOLE_PASSWORD}'" >/dev/null
  echo "Pi-hole password created in Vault (not printed)"
else
  echo "Pi-hole password already present in Vault"
fi

# Upsert Tailscale creds when provided.
if [ -n "${TAILSCALE_OAUTH_CLIENT_ID:-}" ] && [ -n "${TAILSCALE_OAUTH_CLIENT_SECRET:-}" ]; then
  vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault kv put secret/homelab/tailscale client_id='${TAILSCALE_OAUTH_CLIENT_ID}' client_secret='${TAILSCALE_OAUTH_CLIENT_SECRET}'" >/dev/null
  echo "Tailscale creds written to Vault"
else
  echo "Skipping Tailscale creds: set TAILSCALE_OAUTH_CLIENT_ID and TAILSCALE_OAUTH_CLIENT_SECRET"
fi
