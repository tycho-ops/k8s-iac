#!/usr/bin/env bash
set -euo pipefail

YELLOW="\033[1;33m"
GREEN="\033[0;32m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT="${KUBECONTEXT:-admin@eu1-paris-qtrn-io}"

echo -e "${YELLOW}[WARN] Undeploying Quatrain Core documentation stack on ${CONTEXT}...${NC}"
kubectl --context "${CONTEXT}" delete -f "${REPO_ROOT}/k8s/argocd/core-docs-application.yml" --ignore-not-found=true
kubectl --context "${CONTEXT}" delete -k "${REPO_ROOT}/k8s/stacks/core-docs/base" --ignore-not-found=true
echo -e "${GREEN}[SUCCESS] Stack removed cleanly.${NC}"
