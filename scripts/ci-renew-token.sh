#!/bin/bash
# scripts/ci-renew-token.sh
# Versión no interactiva de renew-token para GitHub Actions
# Persiste TODAS las credenciales necesarias en ~/.bashrc del servidor
#
# Variables requeridas (las inyecta el workflow):
#   INFISICAL_CLIENT_ID
#   INFISICAL_CLIENT_SECRET
#   INFISICAL_PROJECT_ID

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${BLUE}[TOKEN]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

: "${INFISICAL_CLIENT_ID:?'INFISICAL_CLIENT_ID no definido'}"
: "${INFISICAL_CLIENT_SECRET:?'INFISICAL_CLIENT_SECRET no definido'}"
: "${INFISICAL_PROJECT_ID:?'INFISICAL_PROJECT_ID no definido'}"

log "Obteniendo token de Infisical (universal-auth)..."

LOGIN_OUTPUT=$(infisical login \
  --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" 2>&1)

NEW_TOKEN=$(echo "$LOGIN_OUTPUT" | grep -oP 'ey[A-Za-z0-9._-]+' | head -1)

if [[ -z "$NEW_TOKEN" ]]; then
  echo "Output del login:"
  echo "$LOGIN_OUTPUT"
  error "No se pudo extraer el token del output de Infisical"
fi

ok "Token obtenido (longitud: ${#NEW_TOKEN})"

# Detectar el directorio del repo (donde está este script)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Generar / actualizar infisical.json en el repo
log "Actualizando infisical.json..."
cat > "$REPO_DIR/infisical.json" << EOF
{
  "workspaceId": "$INFISICAL_PROJECT_ID",
  "defaultEnvironment": "dev",
  "gitBranchToEnvironmentMapping": null
}
EOF

# Limpiar entradas anteriores
sed -i '/^export INFISICAL_TOKEN/d' ~/.bashrc
sed -i '/^export INFISICAL_CLIENT_ID/d' ~/.bashrc
sed -i '/^export INFISICAL_CLIENT_SECRET/d' ~/.bashrc
sed -i '/^export INFISICAL_PROJECT_ID/d' ~/.bashrc
sed -i '/^export TP_REPO_DIR/d' ~/.bashrc
sed -i '/^alias tp-/d' ~/.bashrc

cat >> ~/.bashrc << EOF

#  Tree Pruning -- actualizado por CI $(date '+%Y-%m-%d %H:%M') 
export INFISICAL_CLIENT_ID=$INFISICAL_CLIENT_ID
export INFISICAL_CLIENT_SECRET=$INFISICAL_CLIENT_SECRET
export INFISICAL_PROJECT_ID=$INFISICAL_PROJECT_ID
export INFISICAL_TOKEN="$NEW_TOKEN"
export TP_REPO_DIR="$REPO_DIR"

alias tp-up="cd \$TP_REPO_DIR && infisical run --env=dev --projectId=\$INFISICAL_PROJECT_ID --token=\$INFISICAL_TOKEN -- docker compose up -d"
alias tp-down="cd \$TP_REPO_DIR && docker compose down"
alias tp-ps="cd \$TP_REPO_DIR && infisical run --env=dev --projectId=\$INFISICAL_PROJECT_ID --token=\$INFISICAL_TOKEN -- docker compose ps"
alias tp-logs="docker compose -f \$TP_REPO_DIR/docker-compose.yml logs -f --tail=50"
alias tp-renew-token="\$TP_REPO_DIR/scripts/renew-token.sh"
EOF

export INFISICAL_TOKEN="$NEW_TOKEN"

ok "Token y aliases guardados en ~/.bashrc"
log "El próximo deploy lo renovará automáticamente."
