#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
NC="\033[0m"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info "================================================================="
log_info "Deploying Workload: Quatrain Core Documentation Stack"
log_info "Cluster: $(kubectl config current-context) | Namespace: docs"
log_info "Domains: doc.quatrain.community (alias: docs.quatrain.community, docs.qtrn.io)"
log_info "================================================================="

# 1. Apply stack manifests
log_info "Applying Kubernetes manifests (Deployment, Service, Certificate, IngressRoute)..."
kubectl apply -k "${REPO_ROOT}/k8s/stacks/core-docs/base"

# 2. Register ArgoCD Application
log_info "Registering continuous GitOps delivery in ArgoCD..."
kubectl apply -f "${REPO_ROOT}/k8s/argocd/core-docs-application.yml"

# 3. Wait for rollouts
log_info "Waiting for core-docs rollout..."
kubectl rollout status -n docs deployment/core-docs --timeout=120s

log_success "Quatrain Core Documentation Stack deployed successfully!"
echo ""
echo -e "${BOLD}=== Documentation Endpoints ===${NC}"
echo "• Primary Community URL: https://doc.quatrain.community"
echo "• Community Alias:       https://docs.quatrain.community"
echo "• Fallback Internal URL: https://docs.eu1.paris.qtrn.io"
echo "• Fallback Alias:        https://docs.qtrn.io"
echo ""
echo -e "${BOLD}=== SSL Certificates Status ===${NC}"
kubectl get certificate -n docs
