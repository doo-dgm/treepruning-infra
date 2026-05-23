#!/bin/bash
# scripts/setup-strapi.sh
# Crea el proyecto Strapi dentro del servidor (se corre UNA SOLA VEZ)
#
# Requiere las variables del bootstrap (cargar con: source ~/.bashrc):
#   INFISICAL_TOKEN
#   INFISICAL_PROJECT_ID

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${INFISICAL_TOKEN:?'Exportar INFISICAL_TOKEN primero (source ~/.bashrc)'}"
: "${INFISICAL_PROJECT_ID:?'Exportar INFISICAL_PROJECT_ID primero (source ~/.bashrc)'}"

if [[ -d "$REPO_DIR/strapi-app" ]] && [[ -f "$REPO_DIR/strapi-app/package.json" ]]; then
  ok "strapi-app/ ya existe. Si quieres recrearlo: rm -rf strapi-app/"
  exit 0
fi

# Obtener POSTGRES_PASSWORD de Infisical
log "Obteniendo POSTGRES_PASSWORD de Infisical..."
POSTGRES_PASSWORD=$(infisical secrets get POSTGRES_PASSWORD \
  --env=dev --projectId="$INFISICAL_PROJECT_ID" \
  --token="$INFISICAL_TOKEN" --plain 2>/dev/null | tail -1)

if [[ -z "$POSTGRES_PASSWORD" ]]; then
  error "No se pudo obtener POSTGRES_PASSWORD de Infisical"
fi

# Levantar solo PostgreSQL si no está corriendo
log "Verificando PostgreSQL..."
cd "$REPO_DIR"
if ! docker ps --filter "name=pg1" --filter "status=running" | grep -q pg1; then
  log "Levantando PostgreSQL..."
  infisical run --env=dev --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" \
    -- docker compose up -d pg1
  log "Esperando que PostgreSQL esté listo (20s)..."
  sleep 20
fi

mkdir -p "$REPO_DIR/strapi-app"

# Detectar el nombre de la red Docker (varía según el nombre de la carpeta)
DOCKER_NET=$(docker network ls --filter "name=treepruning-net" --format "{{.Name}}" | head -1)
if [[ -z "$DOCKER_NET" ]]; then
  DOCKER_NET="$(basename "$REPO_DIR")_treepruning-net"
fi
log "Usando red Docker: $DOCKER_NET"

log "Creando proyecto Strapi (esto tarda ~2 minutos)..."
docker run --rm \
  --network "$DOCKER_NET" \
  -v "$REPO_DIR/strapi-app:/app" \
  node:20-alpine \
  sh -c "
    cd /app && \
    npx create-strapi-app@latest . --no-run \
      --dbclient=postgres \
      --dbhost=pg1 \
      --dbport=5432 \
      --dbname=strapi \
      --dbusername=postgres \
      --dbpassword='$POSTGRES_PASSWORD' \
      --skip-cloud \
      --ts \
      --no-example \
      --no-gitinit
  "

# Configurar host de Strapi para escuchar en 0.0.0.0
log "Configurando server.ts de Strapi..."
cat > "$REPO_DIR/strapi-app/config/server.ts" << 'SERVEREOF'
export default ({ env }) => ({
  host: env('HOST', '0.0.0.0'),
  port: env.int('PORT', 1337),
  app: {
    keys: env.array('APP_KEYS'),
  },
});
SERVEREOF

ok "Proyecto Strapi creado en strapi-app/"
echo ""
echo "Ahora ejecutar: tp-up"
