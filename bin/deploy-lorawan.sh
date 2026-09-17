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
log_info "Deploying Optional Workload: LoRaWAN ChirpStack v4 Stack"
log_info "Cluster: $(kubectl config current-context) | Namespace: lorawan"
log_info "================================================================="

# 1. Apply manifests
log_info "Applying Kubernetes manifests (Postgres, Redis, Mosquitto, Gateway Bridge, ChirpStack)..."
kubectl apply -k "${REPO_ROOT}/k8s/stacks/lorawan/base"

# 2. Wait for rollouts
log_info "Waiting for PostgreSQL 16 (on Scaleway SBS 20Gi PVC)..."
kubectl rollout status -n lorawan deployment/postgres --timeout=180s

log_info "Waiting for Redis 7 & Mosquitto MQTT..."
kubectl rollout status -n lorawan deployment/redis --timeout=120s
kubectl rollout status -n lorawan deployment/mosquitto --timeout=120s

log_info "Waiting for ChirpStack Gateway Bridge (LoRa Basics Station WSS)..."
kubectl rollout status -n lorawan deployment/gateway-bridge --timeout=120s

log_info "Waiting for ChirpStack v4 Application & Network Server..."
kubectl rollout status -n lorawan deployment/chirpstack --timeout=120s

# 3. Secure Admin Credential Auto-Provisioning (Zero Default Password Exposure)
log_info "Verifying ChirpStack administrative security credentials..."
SECRET_EXISTS=$(kubectl -n lorawan get secret chirpstack-initial-admin-secret --ignore-not-found -o jsonpath='{.metadata.name}')

if [ -z "$SECRET_EXISTS" ]; then
    log_info "Generating high-entropy random password for ChirpStack administrator..."
    
    # Generate 24-char high-entropy alphanumeric + symbols password
    ADMIN_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!#%&*+-=?@^_~' < /dev/urandom | head -c 24 || true)
    if [ ${#ADMIN_PASS} -lt 20 ]; then
        ADMIN_PASS=$(node -e "const c='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*()-_=+';console.log(Array.from(crypto.getRandomValues(new Uint8Array(24))).map(x=>c[x%c.length]).join(''))" 2>/dev/null || python3 -c "import secrets, string; c=string.ascii_letters+string.digits+'!@#$%^&*()-_=+'; print(''.join(secrets.choice(c) for _ in range(24)))")
    fi
    
    ADMIN_EMAIL="admin"
    
    # Calculate PBKDF2-SHA512 hash (10,000 iterations, 32-byte key)
    PASS_HASH=$(node -e "
      const crypto = require('crypto');
      const pass = process.argv[1];
      const salt = crypto.randomBytes(16);
      const saltB64 = salt.toString('base64').replace(/=+$/, '');
      const key = crypto.pbkdf2Sync(pass, salt, 10000, 32, 'sha512');
      const keyB64 = key.toString('base64').replace(/=+$/, '');
      console.log('\$pbkdf2-sha512\$i=10000,l=32\$' + saltB64 + '\$' + keyB64);
    " "$ADMIN_PASS" 2>/dev/null || python3 -c "
import os, base64, hashlib, sys
pw = sys.argv[1].encode('utf-8')
salt = os.urandom(16)
salt_b64 = base64.b64encode(salt).decode('utf-8').rstrip('=')
key = hashlib.pbkdf2_hmac('sha512', pw, salt, 10000, 32)
key_b64 = base64.b64encode(key).decode('utf-8').rstrip('=')
print(f'\$pbkdf2-sha512\$i=10000,l=32\${salt_b64}\${key_b64}')
    " "$ADMIN_PASS")
    
    # Update PostgreSQL database user
    log_info "Injecting hardened password hash into PostgreSQL 'user' table..."
    kubectl -n lorawan exec deployment/postgres -- psql -U chirpstack -d chirpstack -c "UPDATE \"user\" SET password_hash = '${PASS_HASH}' WHERE is_admin = true OR email = 'admin';" > /dev/null
    
    # Persist in Kubernetes Secret
    kubectl -n lorawan create secret generic chirpstack-initial-admin-secret \
      --from-literal=email="${ADMIN_EMAIL}" \
      --from-literal=password="${ADMIN_PASS}" \
      --dry-run=client -o yaml | kubectl apply -f - > /dev/null
      
    FINAL_EMAIL="${ADMIN_EMAIL}"
    FINAL_PASS="${ADMIN_PASS}"
else
    FINAL_EMAIL=$(kubectl -n lorawan get secret chirpstack-initial-admin-secret -o jsonpath='{.data.email}' | base64 -d)
    FINAL_PASS=$(kubectl -n lorawan get secret chirpstack-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
fi

log_success "🎉 LoRaWAN ChirpStack v4 Stack is 100% RUNNING and Secured!"
echo ""
echo -e "${BOLD}==================== ChirpStack Access Details ====================${NC}"
echo -e "🌐 Web UI URL:        https://eu1.lorawan.qtrn.io"
echo -e "👤 Administrator:     ${FINAL_EMAIL}"
echo -e "🔑 Admin Password:    ${FINAL_PASS}"
echo -e "📡 Basics Station WSS: wss://eu1.lorawan.qtrn.io/traffic"
echo -e "📡 MQTT Broker:        tcp://mosquitto.lorawan.svc.cluster.local:1883"
echo -e "🐘 PostgreSQL Storage: postgres://chirpstack:chirpstack@postgres.lorawan.svc.cluster.local:5432/chirpstack"
echo -e "${BOLD}===================================================================${NC}"
echo ""
