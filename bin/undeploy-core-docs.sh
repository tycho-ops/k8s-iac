#!/usr/bin/env bash
set -euo pipefail

YELLOW="\033[1;33m"
GREEN="\033[0;32m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${YELLOW}[WARN] Undeploying Quatrain Core documentation stack...${NC}"
kubectl delete -f "${REPO_ROOT}/k8s/argocd/core-docs-application.yml" --ignore-not-found=true
kubectl delete -k "${REPO_ROOT}/k8s/stacks/core-docs/base" --ignore-not-found=true
echo -e "${GREEN}[SUCCESS] Stack removed cleanly.${NC}"
