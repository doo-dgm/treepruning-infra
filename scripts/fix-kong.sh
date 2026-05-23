#!/bin/bash
# scripts/fix-kong.sh
# Fix de pg_hba.conf para Kong -- se aplica UNA SOLA VEZ después del primer docker compose up
# Kong no soporta autenticación scram-sha-256, requiere md5
#
# Requiere (cargar con: source ~/.bashrc):
#   INFISICAL_TOKEN
#   INFISICAL_PROJECT_ID

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${INFISICAL_TOKEN:?'Exportar INFISICAL_TOKEN primero (source ~/.bashrc)'}"
: "${INFISICAL_PROJECT_ID:?'Exportar INFISICAL_PROJECT_ID primero (source ~/.bashrc)'}"

warn "Este fix solo debe aplicarse UNA VEZ después del primer arranque."

# Soporta --yes para ejecución no interactiva (CI/CD)
if [[ "${1:-}" != "--yes" ]]; then
  read -p "¿Continuar? [y/N] " -n 1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

log "Verificando que pg1 esté corriendo..."
docker exec pg1 pg_isready -U postgres || { echo "pg1 no está corriendo"; exit 1; }

log "Eliminando regla scram-sha-256 de pg_hba.conf..."
docker exec pg1 bash -c "sed -i '/scram-sha-256/d' /var/lib/postgresql/data/pg_hba.conf"

log "Agregando regla md5..."
docker exec pg1 bash -c "echo 'host all all 0.0.0.0/0 md5' >> /var/lib/postgresql/data/pg_hba.conf"

log "Recargando configuración de PostgreSQL..."
docker exec pg1 psql -U postgres -c "SELECT pg_reload_conf();"

log "Reiniciando Kong y kong-migration..."
cd "$REPO_DIR"
docker compose stop kong kong-migration 2>/dev/null || true
docker compose rm -f kong kong-migration 2>/dev/null || true

log "Levantando kong-migration..."
infisical run --env=dev --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" \
  -- docker compose up -d kong-migration
sleep 15

log "Verificando logs de kong-migration..."
docker logs tp-kong-migration 2>&1 | tail -10

log "Levantando kong..."
infisical run --env=dev --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" \
  -- docker compose up -d kong
sleep 5

ok "Fix de Kong aplicado. Verificar con: docker logs tp-kong --tail=20"
