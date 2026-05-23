#!/bin/bash
# scripts/renew-token.sh
# Renueva el token de Infisical manualmente (expira cada 30 días)
# Usar alias: tp-renew-token
#
# Requiere (cargar con: source ~/.bashrc):
#   INFISICAL_CLIENT_ID
#   INFISICAL_CLIENT_SECRET
#   INFISICAL_PROJECT_ID

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

: "${INFISICAL_CLIENT_ID:?'No definido. Ejecutar: source ~/.bashrc'}"
: "${INFISICAL_CLIENT_SECRET:?'No definido. Ejecutar: source ~/.bashrc'}"
: "${INFISICAL_PROJECT_ID:?'No definido. Ejecutar: source ~/.bashrc'}"

log "Renovando token de Infisical..."

LOGIN_OUTPUT=$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" 2>&1)

NEW_TOKEN=$(echo "$LOGIN_OUTPUT" | grep -oP 'ey[A-Za-z0-9._-]+' | head -1)

if [[ -z "$NEW_TOKEN" ]]; then
  echo "$LOGIN_OUTPUT"
  error "No se pudo obtener el nuevo token"
fi

# Actualizar en .bashrc
sed -i '/^export INFISICAL_TOKEN/d' ~/.bashrc
echo "export INFISICAL_TOKEN=\"$NEW_TOKEN\"" >> ~/.bashrc

ok "Token renovado y guardado en ~/.bashrc"
echo ""
echo "Aplicar en la sesión actual:"
echo "  source ~/.bashrc"
echo "  tp-up"
