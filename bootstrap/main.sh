#!/bin/bash
set -e

echo ">>> Starting Layer 1: Host Bootstrap"

chmod +x *.sh

# Run parts

echo "--- [Base] Updating System ---"
sudo apt-get update -y && sudo apt-get upgrade -y

echo "--- [Base] Installing Common Dependencies ---"
sudo apt-get install -y curl git jq unzip

./k3s/install.sh

echo ">>> Layer 1 Complete. Kubernetes is running."
export KUBECONFIG=~/.kube/config
kubectl get nodes
