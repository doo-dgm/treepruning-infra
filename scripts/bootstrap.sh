#!/bin/bash
# scripts/bootstrap.sh
# ============================================================
# Tree Pruning — Bootstrap completo del servidor desde cero
# Ejecutar UNA SOLA VEZ después de clonar el repo en la VM
#
# Variables de entorno requeridas (exportar antes de ejecutar):
#   INFISICAL_CLIENT_ID
#   INFISICAL_CLIENT_SECRET
#   INFISICAL_PROJECT_ID
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ──────────────────────────────────────────
# 0. Directorio de trabajo
# ──────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
log "Directorio de trabajo: $REPO_DIR"

# ──────────────────────────────────────────
# 1. Variables requeridas
# ──────────────────────────────────────────
: "${INFISICAL_CLIENT_ID:?'ERROR: Exportar INFISICAL_CLIENT_ID antes de ejecutar'}"
: "${INFISICAL_CLIENT_SECRET:?'ERROR: Exportar INFISICAL_CLIENT_SECRET antes de ejecutar'}"
: "${INFISICAL_PROJECT_ID:?'ERROR: Exportar INFISICAL_PROJECT_ID antes de ejecutar'}"

# ──────────────────────────────────────────
# 2. Generar infisical.json
# ──────────────────────────────────────────
log "Generando infisical.json con el Project ID..."
cat > "$REPO_DIR/infisical.json" << EOF
{
  "workspaceId": "$INFISICAL_PROJECT_ID",
  "defaultEnvironment": "dev",
  "gitBranchToEnvironmentMapping": null
}
EOF
ok "infisical.json generado"

# ──────────────────────────────────────────
# 3. Sistema base
# ──────────────────────────────────────────
log "Actualizando sistema..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip htop nano
ok "Sistema actualizado"

# ──────────────────────────────────────────
# 4. Docker
# ──────────────────────────────────────────
if ! command -v docker &> /dev/null; then
  log "Instalando Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  ok "Docker instalado"
else
  ok "Docker ya instalado: $(docker --version)"
fi

# ──────────────────────────────────────────
# 5. SonarQube — kernel param
# ──────────────────────────────────────────
log "Configurando vm.max_map_count para SonarQube..."
sudo sysctl -w vm.max_map_count=262144
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
ok "vm.max_map_count=262144"

# ──────────────────────────────────────────
# 6. Infisical CLI
# ──────────────────────────────────────────
if ! command -v infisical &> /dev/null; then
  log "Instalando Infisical CLI..."
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash
  sudo apt-get update && sudo apt-get install -y infisical
  ok "Infisical CLI instalado: $(infisical --version)"
else
  ok "Infisical CLI ya instalado: $(infisical --version)"
fi

# ──────────────────────────────────────────
# 7. Token de Infisical
# ──────────────────────────────────────────
log "Obteniendo token de Infisical..."
LOGIN_OUTPUT=$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" 2>&1)

INFISICAL_TOKEN=$(echo "$LOGIN_OUTPUT" | grep -oP 'ey[A-Za-z0-9._-]+' | head -1)

if [[ -z "$INFISICAL_TOKEN" ]]; then
  echo "$LOGIN_OUTPUT"
  error "No se pudo obtener el token de Infisical. Verificar credenciales."
fi

export INFISICAL_TOKEN
ok "Token de Infisical obtenido"

# ──────────────────────────────────────────
# 8. Persistir variables en .bashrc
# ──────────────────────────────────────────
log "Guardando variables en ~/.bashrc..."

# Limpiar entradas anteriores
sed -i '/INFISICAL_CLIENT_ID/d' ~/.bashrc
sed -i '/INFISICAL_CLIENT_SECRET/d' ~/.bashrc
sed -i '/INFISICAL_PROJECT_ID/d' ~/.bashrc
sed -i '/INFISICAL_TOKEN/d' ~/.bashrc
sed -i '/TP_REPO_DIR/d' ~/.bashrc
sed -i '/alias tp-/d' ~/.bashrc

cat >> ~/.bashrc << EOF

# ── Tree Pruning ────────────────────────────────
export INFISICAL_CLIENT_ID=$INFISICAL_CLIENT_ID
export INFISICAL_CLIENT_SECRET=$INFISICAL_CLIENT_SECRET
export INFISICAL_PROJECT_ID=$INFISICAL_PROJECT_ID
export INFISICAL_TOKEN="$INFISICAL_TOKEN"
export TP_REPO_DIR="$REPO_DIR"

alias tp-up="cd \$TP_REPO_DIR && infisical run --env=dev --projectId=\$INFISICAL_PROJECT_ID --token=\$INFISICAL_TOKEN -- docker compose up -d"
alias tp-down="cd \$TP_REPO_DIR && docker compose down"
alias tp-ps="cd \$TP_REPO_DIR && infisical run --env=dev --projectId=\$INFISICAL_PROJECT_ID --token=\$INFISICAL_TOKEN -- docker compose ps"
alias tp-logs="docker compose -f \$TP_REPO_DIR/docker-compose.yml logs -f --tail=50"
alias tp-renew-token="\$TP_REPO_DIR/scripts/renew-token.sh"
# ────────────────────────────────────────────────
EOF

ok "Variables y aliases guardados en ~/.bashrc"

# ──────────────────────────────────────────
# 9. Permisos de archivos
# ──────────────────────────────────────────
chmod +x "$REPO_DIR/docker/postgres/init-multiple-dbs.sh"
chmod +x "$REPO_DIR/scripts/"*.sh

# ──────────────────────────────────────────
# 10. Resumen
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Bootstrap completado ✓${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Próximos pasos:"
echo "  1. source ~/.bashrc"
echo "  2. ./scripts/setup-strapi.sh    ← solo si strapi-app/ no existe"
echo "  3. tp-up                         ← levantar todos los servicios"
echo "  4. ./scripts/fix-kong.sh         ← solo en el primer arranque"
echo ""
echo "Nota: si es una sesión nueva de SSH, reconectar para que el grupo docker"
echo "      surta efecto (o ejecutar: newgrp docker)"
