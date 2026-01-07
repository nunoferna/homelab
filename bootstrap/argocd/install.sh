#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "${SCRIPT_DIR}/../.." &> /dev/null && pwd )

ARGOCD_VALUES="${REPO_ROOT}/bootstrap/argocd/values.yaml"
APPOFAPPS="${REPO_ROOT}/gitops/argocd/app-of-apps.yaml"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found"
  exit 1
fi

# Preflight: Helm chart downloads for argo/argo-cd are hosted on GitHub releases.
# If DNS or outbound HTTPS is not working, Helm fails with a confusing error.
if ! curl -fsSLI --connect-timeout 5 --max-time 10 https://github.com >/dev/null 2>&1; then
  echo "ERROR: Cannot reach https://github.com (DNS and/or outbound HTTPS is broken)."
  echo "Helm needs this to download the Argo CD chart from GitHub releases."
  echo
  echo "Debug info:"
  echo "--- /etc/resolv.conf ---"
  cat /etc/resolv.conf 2>/dev/null || true
  echo "-----------------------"
  echo
  echo "Quick checks:"
  echo "  - getent hosts github.com"
  echo "  - ping -c1 1.1.1.1 (tests basic connectivity)"
  echo "  - curl -I https://github.com"
  exit 1
fi

kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

if [ ! -f "${ARGOCD_VALUES}" ]; then
  echo "ArgoCD values file not found: ${ARGOCD_VALUES}"
  exit 1
fi

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.2.4 \
  -f "${ARGOCD_VALUES}"

kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

echo "Applying Argo CD app-of-apps (edit repoURL first): ${APPOFAPPS}"
kubectl apply -f "${APPOFAPPS}"
