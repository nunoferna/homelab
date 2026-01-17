#!/bin/bash
set -euo pipefail

# Never allow command tracing here; it would leak secrets to logs.
set +x

# Unseals Vault using a single unseal key.
# Assumes Vault is running as vault-0 in namespace "vault".

VAULT_NS="vault"
VAULT_POD="vault-0"


KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-5s}"

# In-cluster TLS material is mounted from the vault-server-tls secret.
# cert-manager secrets typically contain tls.crt, tls.key, and (sometimes) ca.crt.
VAULT_TLS_DIR_IN_POD="/vault/tls/vault-server-tls"
VAULT_CACERT_IN_POD="${VAULT_TLS_DIR_IN_POD}/ca.crt"
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

STATE_DIR="${STATE_DIR:-$HOME/.homelab/vault}"
UNSEAL_FILE="${UNSEAL_FILE:-$STATE_DIR/vault-unseal-key}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if [ -z "${VAULT_UNSEAL_KEY:-}" ] && [ -f "${UNSEAL_FILE}" ]; then
  VAULT_UNSEAL_KEY="$(cat "${UNSEAL_FILE}")"
  export VAULT_UNSEAL_KEY
fi

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
  else
    echo
    echo "--- [Vault][Debug] Pod ${VAULT_NS}/${VAULT_POD} not created yet ---"
  fi

  echo
  echo "--- [Vault][Debug] Recent events (${VAULT_NS}) ---"
  kubectl -n "${VAULT_NS}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 50 || true

  echo
  echo "--- [Vault][Debug] ArgoCD app status (if present) ---"
  kubectl -n argocd get application vault -o wide 2>/dev/null || true
  echo
}

echo "--- [Vault] Waiting for pod ${VAULT_NS}/${VAULT_POD} ---"
deadline=$((SECONDS + 600))

# NOTE: Vault's readinessProbe fails while sealed/uninitialized.
# Waiting for condition=Ready would deadlock.
until kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" get pod "${VAULT_POD}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q '^Running$'; do
  if (( SECONDS >= deadline )); then
    echo "ERROR: Timed out waiting for ${VAULT_NS}/${VAULT_POD} to be Running."
    dump_vault_debug
    exit 1
  fi
  sleep 2
done

until kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" exec "${VAULT_POD}" -- /bin/sh -lc "$(vault_cli_env); vault status -format=json 2>/dev/null || true" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "ERROR: Timed out waiting for Vault to respond to 'vault status'."
    dump_vault_debug
    exit 1
  fi
  sleep 2
done

echo "--- [Vault] Checking seal status ---"
STATUS_JSON="$(kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" exec "${VAULT_POD}" -- /bin/sh -lc "$(vault_cli_env); vault status -format=json 2>/dev/null || true" || true)"
SEALED="$(printf '%s' "${STATUS_JSON}" | grep -o '"sealed"\s*:\s*[^,]*' | head -n1 | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}' || true)"
INITIALIZED="$(printf '%s' "${STATUS_JSON}" | grep -o '"initialized"\s*:\s*[^,]*' | head -n1 | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}' || true)"

if [ -z "${INITIALIZED}" ] || [ -z "${SEALED}" ]; then
  echo "ERROR: Could not parse Vault status."
  echo "Raw status output: ${STATUS_JSON}"
  exit 1
fi

if [ "${INITIALIZED}" != "true" ]; then
  echo "Vault is not initialized yet. Run ./bootstrap/vault/init-and-configure.sh once locally."
  exit 1
fi

if [ "${SEALED}" = "false" ]; then
  echo "--- [Vault] Already unsealed ---"
  exit 0
fi

if [ -z "${VAULT_UNSEAL_KEY:-}" ]; then
  echo "Vault is sealed and no unseal key was provided."
  echo "Run ./bootstrap/vault/init-and-configure.sh (it will store ${UNSEAL_FILE}), or set VAULT_UNSEAL_KEY."
  exit 1
fi

echo "--- [Vault] Unsealing ---"
kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" exec -i "${VAULT_POD}" -- /bin/sh -lc "$(vault_cli_env); vault operator unseal '${VAULT_UNSEAL_KEY}'" >/dev/null

echo "--- [Vault] Unseal complete ---"
