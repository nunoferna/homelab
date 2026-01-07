#!/bin/bash
set -euo pipefail

echo "--- [Cilium] Installing Cilium (CNI) ---"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "${SCRIPT_DIR}/../.." &> /dev/null && pwd )

CILIUM_VALUES="${REPO_ROOT}/gitops/apps/cilium/values.yaml"
GATEWAY_API_VERSION="v1.4.1"
GATEWAY_API_CRDS_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# Cache location for the downloaded CRDs:
# - GitHub Actions self-hosted runners often run as non-root; prefer runner-provided dirs.
# - Allow explicit override via GATEWAY_API_CACHE_DIR.
GATEWAY_API_CACHE_DIR_DEFAULT=""
if [ -n "${GATEWAY_API_CACHE_DIR:-}" ]; then
  GATEWAY_API_CACHE_DIR_DEFAULT="${GATEWAY_API_CACHE_DIR}"
elif [ -n "${RUNNER_TEMP:-}" ]; then
  GATEWAY_API_CACHE_DIR_DEFAULT="${RUNNER_TEMP}/homelab/gateway-api/${GATEWAY_API_VERSION}"
elif [ -n "${RUNNER_TOOL_CACHE:-}" ]; then
  GATEWAY_API_CACHE_DIR_DEFAULT="${RUNNER_TOOL_CACHE}/homelab/gateway-api/${GATEWAY_API_VERSION}"
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
  GATEWAY_API_CACHE_DIR_DEFAULT="${XDG_CACHE_HOME}/homelab/gateway-api/${GATEWAY_API_VERSION}"
elif [ -n "${HOME:-}" ]; then
  GATEWAY_API_CACHE_DIR_DEFAULT="${HOME}/.cache/homelab/gateway-api/${GATEWAY_API_VERSION}"
else
  GATEWAY_API_CACHE_DIR_DEFAULT="/tmp/homelab-gateway-api/${GATEWAY_API_VERSION}"
fi

GATEWAY_API_CACHE_DIR="${GATEWAY_API_CACHE_DIR_DEFAULT}"
GATEWAY_API_CACHE_FILE="${GATEWAY_API_CACHE_DIR}/standard-install.yaml"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found"
  exit 1
fi

if [ ! -f "${CILIUM_VALUES}" ]; then
  echo "Cilium values file not found: ${CILIUM_VALUES}"
  exit 1
fi

echo "--- [Gateway API] Installing Gateway API CRDs (${GATEWAY_API_VERSION}) ---"
# Required because Cilium can create Gateway API resources (e.g. GatewayClass),
# but Kubernetes does not ship these CRDs by default.
if ! mkdir -p "${GATEWAY_API_CACHE_DIR}"; then
  GATEWAY_API_CACHE_DIR="/tmp/homelab-gateway-api/${GATEWAY_API_VERSION}"
  GATEWAY_API_CACHE_FILE="${GATEWAY_API_CACHE_DIR}/standard-install.yaml"
  mkdir -p "${GATEWAY_API_CACHE_DIR}"
fi

if [ ! -f "${GATEWAY_API_CACHE_FILE}" ]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found (needed to download Gateway API CRDs)"
    exit 1
  fi

  echo "Downloading Gateway API CRDs to ${GATEWAY_API_CACHE_FILE}"
  for attempt in 1 2 3 4 5; do
    tmpfile="${GATEWAY_API_CACHE_FILE}.tmp.$$"
    if curl -fsSL --connect-timeout 5 --max-time 60 -o "${tmpfile}" "${GATEWAY_API_CRDS_URL}"; then
      mv "${tmpfile}" "${GATEWAY_API_CACHE_FILE}"
      break
    fi
    echo "Download attempt ${attempt} failed; retrying in 3s..."
    sleep 3
  done

  if [ ! -f "${GATEWAY_API_CACHE_FILE}" ]; then
    echo "Failed to download Gateway API CRDs from: ${GATEWAY_API_CRDS_URL}"
    exit 1
  fi
fi

kubectl apply -f "${GATEWAY_API_CACHE_FILE}"
kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=5m

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.5 \
  -f "${CILIUM_VALUES}"

kubectl -n kube-system rollout status ds/cilium --timeout=10m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=10m

echo "--- [Cilium] Installed and ready ---"
