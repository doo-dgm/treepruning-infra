#!/bin/bash
# =============================================================================
# scripts/migrate-to-sqlserver.sh
# Migra los datos de pg1 a SQL Server para habilitar el failover.
#
# Qué hace:
#   1. Crea las bases de datos en SQL Server
#   2. Aplica el esquema treepruning (dbo) en SQL Server
#   3. Exporta el realm de Keycloak y lo importa en SQL Server
#   4. Arranca Strapi y SonarQube brevemente contra SQL Server para crear sus esquemas
#   5. Corre el script Python de migración de datos (treepruning, strapi, sonarqube)
#   6. Verifica que todo quedó bien
#
# Prerequisitos:
#   - Infisical CLI instalado y con sesión activa
#   - Docker Compose stack corriendo con pg1 saludable
#   - tp-sqlserver corriendo y saludable
#
# Uso:
#   cd ~/treepruning-infra
#   source ~/.bashrc  # cargar INFISICAL_TOKEN e INFISICAL_PROJECT_ID
#   ./scripts/migrate-to-sqlserver.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}══════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════════${NC}"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQLSERVER_DIR="$REPO_DIR/docker/sqlserver"
MIGRATE_DIR="$SQLSERVER_DIR/migrate"
BACKUP_DIR="$REPO_DIR/.migration-backup-$(date +%Y%m%d-%H%M%S)"

: "${INFISICAL_TOKEN:?'Exportar INFISICAL_TOKEN primero'}"
: "${INFISICAL_PROJECT_ID:?'Exportar INFISICAL_PROJECT_ID primero'}"

mkdir -p "$BACKUP_DIR"

# ── Cargar secrets desde Infisical ───────────────────────────────────────────
step "Cargando secrets desde Infisical"

get_secret() {
    infisical secrets get "$1" \
      --env=dev --projectId="$INFISICAL_PROJECT_ID" \
      --token="$INFISICAL_TOKEN" --plain 2>/dev/null | tail -1
}

PG_USER=$(get_secret "POSTGRES_USER")
PG_PASS=$(get_secret "POSTGRES_PASSWORD")
PG_DB=$(get_secret "POSTGRES_DB")
SQL_PASS=$(get_secret "SQLSERVER_PASSWORD")

[[ -z "$PG_USER" ]]  && error "No se pudo obtener POSTGRES_USER"
[[ -z "$PG_PASS" ]]  && error "No se pudo obtener POSTGRES_PASSWORD"
[[ -z "$SQL_PASS" ]] && error "No se pudo obtener SQLSERVER_PASSWORD"

ok "Secrets cargados"

# ── Verificar que los contenedores estén corriendo ────────────────────────────
step "Verificando contenedores"

for container in pg1 tp-sqlserver; do
    if ! docker ps --filter "name=${container}" --filter "status=running" | grep -q "${container}"; then
        error "Contenedor ${container} no está corriendo. Levantar primero: docker compose up -d ${container}"
    fi
    ok "${container} corriendo"
done

# ── PASO 1: Crear bases de datos en SQL Server ────────────────────────────────
step "Paso 1/5 — Creando bases de datos en SQL Server"

docker exec tp-sqlserver \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SQL_PASS" -C \
    -i /dev/stdin << 'EOF'
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'keycloak')
    CREATE DATABASE keycloak COLLATE Latin1_General_100_CI_AS_SC_UTF8;
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'strapi')
    CREATE DATABASE strapi COLLATE Latin1_General_100_CI_AS_SC_UTF8;
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'sonarqube')
    CREATE DATABASE sonarqube COLLATE Latin1_General_100_CI_AS_SC_UTF8;
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'treepruning')
    CREATE DATABASE treepruning COLLATE Latin1_General_100_CI_AS_SC_UTF8;
SELECT name FROM sys.databases WHERE name IN ('keycloak','strapi','sonarqube','treepruning');
GO
EOF

ok "Bases de datos creadas en SQL Server"

# ── PASO 2: Esquema treepruning en SQL Server ─────────────────────────────────
step "Paso 2/5 — Aplicando esquema treepruning en SQL Server"

# Copiar el script al contenedor y ejecutarlo
docker cp "$SQLSERVER_DIR/init-treepruning.sql" tp-sqlserver:/tmp/init-treepruning.sql
docker exec tp-sqlserver \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SQL_PASS" -C \
    -d treepruning \
    -i /tmp/init-treepruning.sql

ok "Esquema treepruning aplicado en SQL Server"

# ── PASO 3: Migrar Keycloak (export desde KC → import a KC con SQL Server) ───
step "Paso 3/5 — Migrando Keycloak"

log "Exportando realm de Keycloak desde pg1..."
docker exec tp-keycloak \
    /opt/keycloak/bin/kc.sh export \
    --dir /tmp/kc-export \
    --realm tree-pruning \
    --users realm_file 2>&1 | tail -5

docker cp tp-keycloak:/tmp/kc-export "$BACKUP_DIR/kc-export"
ok "Realm exportado a $BACKUP_DIR/kc-export"

log "Iniciando Keycloak temporal contra SQL Server para crear esquema..."
KC_SQLSERVER_URL="jdbc:sqlserver://tp-sqlserver:1433;databaseName=keycloak;encrypt=false;trustServerCertificate=true"

# Arrancar keycloak temporal (diferente nombre de contenedor)
docker run --rm -d \
    --name tp-keycloak-migrate \
    --network "$(docker inspect tp-keycloak --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' | head -1)" \
    -e KEYCLOAK_ADMIN=admin \
    -e KEYCLOAK_ADMIN_PASSWORD=admin_migrate_tmp \
    -e KC_DB=mssql \
    -e KC_DB_URL="$KC_SQLSERVER_URL" \
    -e KC_DB_USERNAME=sa \
    -e KC_DB_PASSWORD="$SQL_PASS" \
    -e KC_HTTP_ENABLED=true \
    -e KC_HOSTNAME_STRICT=false \
    quay.io/keycloak/keycloak:24.0 \
    start-dev 2>&1 | tail -3

log "Esperando que Keycloak cree el esquema en SQL Server (60s)..."
sleep 60

log "Importando realm a SQL Server..."
docker cp "$BACKUP_DIR/kc-export" tp-keycloak-migrate:/tmp/kc-import
docker exec tp-keycloak-migrate \
    /opt/keycloak/bin/kc.sh import \
    --dir /tmp/kc-import 2>&1 | tail -10

docker stop tp-keycloak-migrate 2>/dev/null || true
ok "Keycloak migrado a SQL Server"

# ── PASO 4: Crear esquemas Strapi y SonarQube en SQL Server ──────────────────
step "Paso 4/5 — Creando esquemas Strapi y SonarQube en SQL Server"

DOCKER_NET=$(docker inspect tp-sqlserver --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' | head -1)

log "Arrancando Strapi temporal contra SQL Server (crea tablas automáticamente)..."
docker run --rm -d \
    --name tp-strapi-migrate \
    --network "$DOCKER_NET" \
    -e DATABASE_CLIENT=mssql \
    -e DATABASE_HOST=tp-sqlserver \
    -e DATABASE_PORT=1433 \
    -e DATABASE_NAME=strapi \
    -e DATABASE_USERNAME=sa \
    -e DATABASE_PASSWORD="$SQL_PASS" \
    -e DATABASE_SSL=false \
    -e JWT_SECRET=migrate-tmp-secret \
    -e ADMIN_JWT_SECRET=migrate-tmp-secret \
    -e APP_KEYS=migrate-tmp-key1,migrate-tmp-key2 \
    -e NODE_ENV=development \
    -v "$REPO_DIR/strapi-app:/app" \
    node:20-alpine \
    sh -c "cd /app && npm run develop" 2>&1 | tail -3

log "Esperando que Strapi cree el esquema en SQL Server (90s)..."
sleep 90
docker stop tp-strapi-migrate 2>/dev/null || true
ok "Esquema Strapi creado en SQL Server"

log "Arrancando SonarQube temporal contra SQL Server (crea tablas automáticamente)..."
SONAR_SQLSERVER_URL="jdbc:sqlserver://tp-sqlserver:1433;databaseName=sonarqube;encrypt=false;trustServerCertificate=true"

docker run --rm -d \
    --name tp-sonarqube-migrate \
    --network "$DOCKER_NET" \
    -e SONAR_JDBC_URL="$SONAR_SQLSERVER_URL" \
    -e SONAR_JDBC_USERNAME=sa \
    -e SONAR_JDBC_PASSWORD="$SQL_PASS" \
    sonarqube:26.5.0.122743-community 2>&1 | tail -3

log "Esperando que SonarQube cree el esquema en SQL Server (3 min)..."
sleep 180
docker stop tp-sonarqube-migrate 2>/dev/null || true
ok "Esquema SonarQube creado en SQL Server"

# ── PASO 5: Migrar datos (treepruning, strapi, sonarqube) ────────────────────
step "Paso 5/5 — Migrando datos con el script Python"

docker cp "$MIGRATE_DIR/migrate_pg_to_sqlserver.py" tp-sqlserver:/tmp/migrate.py 2>/dev/null || true

log "Corriendo migración de datos..."
docker run --rm \
    --network "$DOCKER_NET" \
    -e PG_HOST=pg1 \
    -e PG_USER="$PG_USER" \
    -e PG_PASSWORD="$PG_PASS" \
    -e SQL_HOST=tp-sqlserver \
    -e SQL_USER=sa \
    -e SQL_PASSWORD="$SQL_PASS" \
    -v "$MIGRATE_DIR/migrate_pg_to_sqlserver.py:/app/migrate.py:ro" \
    python:3.12-slim \
    sh -c "pip install psycopg2-binary pymssql -q && python /app/migrate.py"

ok "Migración de datos completada"

# ── Verificación final ────────────────────────────────────────────────────────
step "Verificación final"

log "Conteo de filas en SQL Server (treepruning)..."
docker exec tp-sqlserver \
    /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SQL_PASS" -C \
    -d treepruning -Q "
SELECT t.name, p.rows AS total_filas
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE t.type = 'U' AND p.index_id IN (0,1)
ORDER BY p.rows DESC;
"

echo ""
ok "══════════════════════════════════════════════"
ok " Migración completada exitosamente"
ok " Backup guardado en: $BACKUP_DIR"
ok ""
ok " Próximo paso: actualizar el compose para"
ok " que use SQL Server como failover."
ok "══════════════════════════════════════════════"
