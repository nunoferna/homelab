#!/bin/sh
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.vault.svc:8200}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found"
  exit 1
fi

curl_ca_opt() {
  if [ -n "${VAULT_CACERT:-}" ]; then
    echo "--cacert ${VAULT_CACERT}"
    return
  fi
  if [ "${VAULT_SKIP_VERIFY:-}" = "true" ]; then
    echo "--insecure"
    return
  fi
  echo ""
}

login_with_approle() {
  CURL_CA_OPT="$(curl_ca_opt)"
  if [ -z "${VAULT_APPROLE_ROLE_ID:-}" ] || [ -z "${VAULT_APPROLE_SECRET_ID:-}" ]; then
    return 1
  fi
  curl -sS --request POST \
    ${CURL_CA_OPT} \
    --data "{\"role_id\":\"${VAULT_APPROLE_ROLE_ID}\",\"secret_id\":\"${VAULT_APPROLE_SECRET_ID}\"}" \
    "${VAULT_ADDR}/v1/auth/approle/login" | jq -r '.auth.client_token'
}

if [ -z "${VAULT_TOKEN:-}" ]; then
  VAULT_TOKEN="$(login_with_approle || true)"
fi

if [ -z "${VAULT_TOKEN:-}" ] || [ "${VAULT_TOKEN}" = "null" ]; then
  echo "VAULT_TOKEN or VAULT_APPROLE_ROLE_ID/VAULT_APPROLE_SECRET_ID required"
  exit 1
fi

CA_B64="$(curl -sS $(curl_ca_opt) -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/homelab/ca" | jq -r '.data.data.ca_pem_b64')"

if [ -z "${CA_B64}" ] || [ "${CA_B64}" = "null" ]; then
  echo "CA not found in Vault at secret/homelab/ca (ca_pem_b64)"
  exit 1
fi

TMP_CA="/tmp/homelab-ca.crt"
printf '%s' "${CA_B64}" | base64 -d > "${TMP_CA}"

if [ "$(uname -s)" = "Darwin" ]; then
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "${TMP_CA}"
  echo "CA installed into macOS System keychain."
  exit 0
fi

if [ -f /etc/debian_version ]; then
  sudo cp "${TMP_CA}" /usr/local/share/ca-certificates/homelab-ca.crt
  sudo update-ca-certificates
  echo "CA installed for Debian/Ubuntu."
  exit 0
fi

if [ -f /etc/redhat-release ]; then
  sudo cp "${TMP_CA}" /etc/pki/ca-trust/source/anchors/homelab-ca.crt
  sudo update-ca-trust
  echo "CA installed for RHEL/Fedora."
  exit 0
fi

echo "Unsupported OS. CA saved at ${TMP_CA}"
