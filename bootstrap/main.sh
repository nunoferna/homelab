#!/bin/bash
set -e

echo ">>> Starting Layer 1: Host Bootstrap"

chmod +x *.sh
chmod +x argocd/*.sh 2>/dev/null || true
chmod +x cilium/*.sh 2>/dev/null || true
chmod +x vault/*.sh 2>/dev/null || true
chmod +x clients/*.sh 2>/dev/null || true

# Run parts

echo "--- [Base] Updating System ---"
sudo apt-get update -y && sudo apt-get upgrade -y

echo "--- [Base] Installing Common Dependencies ---"
sudo apt-get install -y curl git jq unzip openssl

echo "--- [Base] Installing Helm ---"
if ! command -v helm &> /dev/null; then
    echo "Installing Helm via Apt..."
    sudo apt-get install -y apt-transport-https gpg
    curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm
else
    echo "Helm is already installed."
fi

./k3s/install.sh

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

echo "--- [K3s] Waiting for Kubernetes API to respond ---"
api_deadline=$((SECONDS + 300))
until kubectl version --request-timeout=5s >/dev/null 2>&1; do
    if (( SECONDS >= api_deadline )); then
        echo "ERROR: Timed out waiting for Kubernetes API."
        sudo journalctl -u k3s --no-pager -n 200 2>/dev/null || true
        exit 1
    fi
    sleep 2
done

echo "--- [K3s] Waiting for Node resource to appear ---"
node_deadline=$((SECONDS + 300))
until kubectl get nodes -o name 2>/dev/null | grep -q '^node/'; do
    if (( SECONDS >= node_deadline )); then
        echo "ERROR: Timed out waiting for node resource to be created."
        kubectl get all -A 2>/dev/null || true
        sudo journalctl -u k3s --no-pager -n 200 2>/dev/null || true
        exit 1
    fi
    sleep 2
done

./cilium/install.sh

if [ -f "./clients/install-ca.sh" ]; then
    if [ -n "${VAULT_TOKEN:-}" ] || { [ -n "${VAULT_APPROLE_ROLE_ID:-}" ] && [ -n "${VAULT_APPROLE_SECRET_ID:-}" ]; }; then
        echo "--- [Clients] Installing homelab CA ---"
        ./clients/install-ca.sh
    else
        echo "--- [Clients] Skipping CA install (missing Vault credentials) ---"
    fi
fi

echo "--- [DNS] Waiting for CoreDNS to be Available ---"
kubectl -n kube-system rollout status deploy/coredns --timeout=5m

echo "--- [DNS] Sanity check: resolve github.com from inside the cluster ---"
if ! kubectl run dns-test \
    --rm -i --restart=Never \
    --image=busybox:1.36 \
    --command -- nslookup github.com >/dev/null 2>&1; then
    echo "ERROR: In-cluster DNS resolution failed (nslookup github.com)."
    echo
    echo "CoreDNS logs (last 120 lines):"
    kubectl -n kube-system logs deploy/coredns --tail=120 2>/dev/null || true
    echo
    echo "CoreDNS Corefile:"
    kubectl -n kube-system get cm coredns -o yaml 2>/dev/null | sed -n '1,200p' || true
    echo
    echo "Hint: if you see CoreDNS upstream i/o timeouts, pod egress NAT/masquerade is usually broken."
    exit 1
fi

echo "--- [K3s] Waiting for node to be Ready ---"
kubectl wait --for=condition=Ready node --all --timeout=10m

echo ">>> Layer 1 Complete. Kubernetes is running."
kubectl get nodes
