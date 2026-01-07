#!/bin/bash
set -euo pipefail

# Never allow command tracing here; it would leak secrets to logs.
set +x

# One-time Vault bootstrap for this homelab.
# - Initializes Vault (if needed) and writes init output to a local file (0600)
# - Unseals Vault
# - Enables KV v2 at secret/
# - Configures Kubernetes auth for External Secrets Operator (ESO)
# - Enables AppRole auth for CI (GitHub runner)
#
# This script is safe to run in GitHub Actions on a self-hosted runner:
# it will NOT print sensitive values. It stores them locally on the runner host.

VAULT_NS="vault"
VAULT_POD="vault-0"

KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-5s}"

STATE_DIR="${STATE_DIR:-$HOME/.homelab/vault}"
INIT_OUT_FILE="${INIT_OUT_FILE:-$STATE_DIR/vault-init.json}"
CREDS_FILE="${CREDS_FILE:-$STATE_DIR/vault-approle.json}"
UNSEAL_FILE="${UNSEAL_FILE:-$STATE_DIR/vault-unseal-key}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found"
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

ensure_vault_pod() {
  local deadline
  deadline=$((SECONDS + 600))

  # NOTE: Vault's readinessProbe runs `vault status` and fails while sealed/uninitialized.
  # Waiting for condition=Ready would deadlock the bootstrap.
  echo "Waiting for pod ${VAULT_NS}/${VAULT_POD} to be Running..."
  until kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" get pod "${VAULT_POD}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q '^Running$'; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: Timed out waiting for ${VAULT_NS}/${VAULT_POD} to be Running."
      dump_vault_debug
      exit 1
    fi
    # Keep progress output short but useful.
    kubectl -n "${VAULT_NS}" --request-timeout="${KUBECTL_TIMEOUT}" get pod "${VAULT_POD}" -o wide 2>/dev/null || true
    sleep 2
  done

  echo "Waiting for vault process to accept exec..."
  # IMPORTANT: `vault status` returns a non-zero exit code when sealed/uninitialized.
  # We only need the process to be up and able to return parseable JSON.
  until vault_exec_no_stdin "export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json 2>/dev/null || true" | jq -e . >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: Timed out waiting for Vault to respond to 'vault status'."
      dump_vault_debug
      exit 1
    fi
    sleep 2
  done
}

kube_current_cluster() {
  local ctx cluster
  ctx="$(kubectl config current-context)"
  cluster="$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${ctx}')].context.cluster}")"
  echo "$cluster"
}

kube_server() {
  local cluster
  cluster="$(kube_current_cluster)"
  kubectl config view -o jsonpath="{.clusters[?(@.name=='${cluster}')].cluster.server}"
}

kube_ca_data() {
  local cluster
  cluster="$(kube_current_cluster)"
  kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='${cluster}')].cluster.certificate-authority-data}"
}

echo "--- [Vault] Waiting for ${VAULT_NS}/${VAULT_POD} ---"
ensure_vault_pod

mkdir -p "${STATE_DIR}"
chmod 700 "${STATE_DIR}"

echo "--- [Vault] Checking init status ---"
if vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json" | jq -e '.initialized == true' >/dev/null 2>&1; then
  echo "Vault already initialized."
else
  echo "--- [Vault] Initializing (1 key share / 1 threshold) ---"
  vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; vault operator init -key-shares=1 -key-threshold=1 -format=json" > "${INIT_OUT_FILE}"
  chmod 600 "${INIT_OUT_FILE}"
  echo "Wrote init output to ${INIT_OUT_FILE} (mode 0600)"
fi

ROOT_TOKEN="$(jq -r '.root_token // empty' "${INIT_OUT_FILE}" 2>/dev/null || true)"
UNSEAL_KEY="$(jq -r '.unseal_keys_b64[0] // empty' "${INIT_OUT_FILE}" 2>/dev/null || true)"

if [ -z "${ROOT_TOKEN}" ] && vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; vault status -format=json" | jq -e '.initialized == true' >/dev/null 2>&1; then
  echo "Vault is initialized but ${INIT_OUT_FILE} does not contain root_token."
  echo "You need an admin token to proceed (or re-init by wiping the Vault PVC)."
  exit 1
fi

if [ -z "${UNSEAL_KEY}" ]; then
  echo "UNSEAL_KEY not found in ${INIT_OUT_FILE}."
  echo "If Vault is already unsealed, you can ignore this; otherwise you need the unseal key."
else
  printf '%s' "${UNSEAL_KEY}" > "${UNSEAL_FILE}"
  chmod 600 "${UNSEAL_FILE}"
  echo "--- [Vault] Unsealing (idempotent) ---"
  vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; vault operator unseal '${UNSEAL_KEY}'" >/dev/null || true
fi

export VAULT_TOKEN="${ROOT_TOKEN}"

echo "--- [Vault] Enabling KV v2 at secret/ (if missing) ---"
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault secrets list -format=json | grep -q '\"secret/\"' || vault secrets enable -path=secret kv-v2" >/dev/null

echo "--- [Vault] Creating policies ---"
# Read policy for ESO
vault_exec "cat > /tmp/external-secrets-read.hcl <<'EOF'
path \"secret/data/homelab/*\" { capabilities = [\"read\"] }
path \"secret/metadata/homelab/*\" { capabilities = [\"list\", \"read\"] }
EOF" >/dev/null
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault policy write external-secrets-read /tmp/external-secrets-read.hcl" >/dev/null

# Write policy for CI (GitHub runner)
vault_exec "cat > /tmp/homelab-writer.hcl <<'EOF'
path \"secret/data/homelab/*\" { capabilities = [\"create\", \"update\", \"read\"] }
path \"secret/metadata/homelab/*\" { capabilities = [\"list\", \"read\"] }
EOF" >/dev/null
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault policy write homelab-writer /tmp/homelab-writer.hcl" >/dev/null

echo "--- [Vault] Configuring Kubernetes auth for ESO ---"
# Create token reviewer SA + binding
kubectl -n "${VAULT_NS}" get sa vault-auth >/dev/null 2>&1 || kubectl -n "${VAULT_NS}" create sa vault-auth
kubectl get clusterrolebinding vault-auth-delegator >/dev/null 2>&1 || kubectl create clusterrolebinding vault-auth-delegator --clusterrole=system:auth-delegator --serviceaccount="${VAULT_NS}":vault-auth

JWT="$(kubectl -n "${VAULT_NS}" create token vault-auth)"
# IMPORTANT: Configure Vault using the in-cluster Kubernetes service endpoint.
# If we use the kubeconfig server URL from the runner (often https://127.0.0.1:6443),
# Vault inside the cluster won't be able to reach it, and ESO auth will fail.
KUBE_HOST="https://kubernetes.default.svc:443"
KUBE_CA_CERT_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault auth list -format=json | grep -q '\"kubernetes/\"' || vault auth enable kubernetes" >/dev/null
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault write auth/kubernetes/config token_reviewer_jwt='${JWT}' kubernetes_host='${KUBE_HOST}' kubernetes_ca_cert=@${KUBE_CA_CERT_FILE}" >/dev/null

# Create ESO role bound to the ESO service account in external-secrets namespace
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault write auth/kubernetes/role/external-secrets bound_service_account_names=external-secrets bound_service_account_namespaces=external-secrets policies=external-secrets-read ttl=24h" >/dev/null

echo "--- [Vault] Configuring AppRole auth for CI (GitHub runner) ---"
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault auth list -format=json | grep -q '\"approle/\"' || vault auth enable approle" >/dev/null
vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault write auth/approle/role/homelab-ci token_policies=homelab-writer token_ttl=1h token_max_ttl=24h" >/dev/null

ROLE_ID="$(vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault read -format=json auth/approle/role/homelab-ci/role-id" | jq -r '.data.role_id')"
SECRET_ID="$(vault_exec "export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN='${VAULT_TOKEN}'; vault write -format=json -f auth/approle/role/homelab-ci/secret-id" | jq -r '.data.secret_id')"

cat > "${CREDS_FILE}" <<EOF
{"role_id":"${ROLE_ID}","secret_id":"${SECRET_ID}"}
EOF
chmod 600 "${CREDS_FILE}"

echo "--- Done ---"
echo "Stored Vault init output at: ${INIT_OUT_FILE}"
echo "Stored Vault unseal key at: ${UNSEAL_FILE}"
echo "Stored Vault AppRole creds at: ${CREDS_FILE}"
echo "(These files stay on the self-hosted runner; values are not printed.)"
