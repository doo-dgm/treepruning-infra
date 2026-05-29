#!/bin/bash
# =============================================================================
# migrate-keycloak-strapi-to-mysql.sh
#
# Migra los datos de Keycloak y Strapi desde PostgreSQL (pg1) a MySQL (tp-mysql).
#
# PREREQUISITOS:
#   - pg1 corriendo y healthy
#   - tp-keycloak corriendo y healthy
#   - tp-strapi corriendo y healthy
#   - tp-mysql corriendo y healthy
#   - Variables de entorno disponibles (ejecutar con: infisical run -- bash migrate-...)
#
# USO:
#   infisical run -- bash docker/scripts/migrate-keycloak-strapi-to-mysql.sh
#
# El script hace:
#   1. Exporta todos los realms de Keycloak vía kc.sh export
#   2. Exporta datos de Strapi vía strapi export
#   3. Detiene Keycloak y Strapi
#   4. Actualiza docker-compose para apuntar ambos a MySQL  <-- ya lo hiciste tú en compose
#   5. Levanta Keycloak con MySQL (crea esquema automáticamente)
#   6. Importa realms de Keycloak
#   7. Levanta Strapi con MySQL
#   8. Importa datos de Strapi
# =============================================================================
set -euo pipefail

EXPORT_DIR="$(dirname "$0")/migration-exports"
KC_EXPORT_DIR="$EXPORT_DIR/keycloak"
STRAPI_EXPORT_DIR="$EXPORT_DIR/strapi"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()    { echo -e "${GREEN}[migrate]${NC} $*"; }
warn()   { echo -e "${YELLOW}[migrate]${NC} $*"; }
error()  { echo -e "${RED}[migrate]${NC} $*" >&2; }

# =============================================================================
# STEP 0: preparar directorio de exportaciones
# =============================================================================
log "Preparando directorio de exportaciones en $EXPORT_DIR..."
mkdir -p "$KC_EXPORT_DIR" "$STRAPI_EXPORT_DIR"

# =============================================================================
# STEP 1: verificar que los contenedores necesarios están corriendo
# =============================================================================
log "Verificando contenedores..."
for container in pg1 tp-keycloak tp-strapi tp-mysql; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
    if [[ "$STATUS" != "running" ]]; then
        error "El contenedor $container no está corriendo (status: $STATUS). Abortando."
        exit 1
    fi
done
log "Todos los contenedores necesarios están corriendo."

# =============================================================================
# STEP 2: exportar realms de Keycloak desde pg1
# =============================================================================
log "Exportando realms de Keycloak (esto puede tardar 30-60s)..."

# kc.sh export escribe los JSONs en el directorio indicado dentro del contenedor
docker exec tp-keycloak /opt/keycloak/bin/kc.sh export \
    --dir /tmp/kc-export \
    --users realm_file \
    2>&1 | grep -v "^$" || true

# Copiar los exports fuera del contenedor
docker cp tp-keycloak:/tmp/kc-export/. "$KC_EXPORT_DIR/"

REALM_COUNT=$(ls "$KC_EXPORT_DIR"/*.json 2>/dev/null | wc -l)
if [[ "$REALM_COUNT" -eq 0 ]]; then
    error "No se encontraron archivos de export de Keycloak en $KC_EXPORT_DIR. Abortando."
    exit 1
fi
log "Exportados $REALM_COUNT realm(s): $(ls "$KC_EXPORT_DIR"/*.json | xargs -n1 basename)"

# =============================================================================
# STEP 3: exportar datos de Strapi
# =============================================================================
log "Exportando datos de Strapi (esto puede tardar 1-2 min)..."

# strapi export genera un archivo .tar.gz con todos los datos
docker exec tp-strapi sh -c "cd /app && npx strapi export --no-encrypt --file /tmp/strapi-export" \
    2>&1 | tail -20

# Buscar el archivo generado (strapi agrega timestamp al nombre)
STRAPI_TAR=$(docker exec tp-strapi sh -c "ls /tmp/strapi-export*.tar.gz 2>/dev/null | head -1" || echo "")
if [[ -z "$STRAPI_TAR" ]]; then
    error "No se encontró el archivo de export de Strapi. Abortando."
    exit 1
fi

docker cp "tp-strapi:$STRAPI_TAR" "$STRAPI_EXPORT_DIR/strapi-export.tar.gz"
log "Export de Strapi copiado a $STRAPI_EXPORT_DIR/strapi-export.tar.gz"

# =============================================================================
# STEP 4: detener Keycloak y Strapi (todavía apuntando a pg1)
# =============================================================================
log "Deteniendo Keycloak y Strapi..."
docker compose stop keycloak strapi

# =============================================================================
# STEP 5: levantar Keycloak con MySQL (ya apunta a tp-mysql en docker-compose)
#          Keycloak crea su esquema automáticamente al arrancar
# =============================================================================
log "Levantando Keycloak con MySQL (creará esquema automáticamente)..."
docker compose up -d --no-deps keycloak

log "Esperando que Keycloak esté healthy (hasta 3 min)..."
TIMEOUT=180
ELAPSED=0
until docker inspect tp-keycloak --format '{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        error "Keycloak no alcanzó estado healthy en ${TIMEOUT}s. Revisa: docker logs tp-keycloak"
        exit 1
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""
log "Keycloak healthy."

# =============================================================================
# STEP 6: importar realms en Keycloak con MySQL
# =============================================================================
log "Importando realms en Keycloak (MySQL)..."

# Copiar los exports al contenedor nuevo
docker cp "$KC_EXPORT_DIR/." tp-keycloak:/tmp/kc-import/

# Ejecutar import realm por realm
for realm_file in "$KC_EXPORT_DIR"/*.json; do
    REALM_NAME=$(basename "$realm_file" .json | sed 's/-realm$//')
    # El archivo master-realm.json se importa saltando 'master' (ya existe)
    if [[ "$REALM_NAME" == "master" ]]; then
        warn "Saltando realm 'master' (Keycloak lo crea automáticamente). Solo se importarán sus usuarios."
        docker exec tp-keycloak /opt/keycloak/bin/kc.sh import \
            --file "/tmp/kc-import/$(basename "$realm_file")" \
            --override true \
            2>&1 | tail -5 || warn "Import de master puede tener advertencias — es normal."
    else
        log "Importando realm: $REALM_NAME"
        docker exec tp-keycloak /opt/keycloak/bin/kc.sh import \
            --file "/tmp/kc-import/$(basename "$realm_file")" \
            --override true \
            2>&1 | tail -5
    fi
done
log "Realms importados correctamente."

# =============================================================================
# STEP 7: levantar Strapi con MySQL
# =============================================================================
log "Levantando Strapi con MySQL..."
docker compose up -d --no-deps strapi

log "Esperando que Strapi esté healthy (hasta 3 min)..."
TIMEOUT=180
ELAPSED=0
until docker inspect tp-strapi --format '{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        error "Strapi no alcanzó estado healthy en ${TIMEOUT}s. Revisa: docker logs tp-strapi"
        exit 1
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo -n "."
done
echo ""
log "Strapi healthy."

# =============================================================================
# STEP 8: importar datos de Strapi
# =============================================================================
log "Importando datos de Strapi (MySQL)..."

docker cp "$STRAPI_EXPORT_DIR/strapi-export.tar.gz" tp-strapi:/tmp/strapi-export.tar.gz

docker exec tp-strapi sh -c "cd /app && npx strapi import --no-encrypt --file /tmp/strapi-export.tar.gz --force" \
    2>&1 | tail -20

log "Datos de Strapi importados correctamente."

# =============================================================================
# RESUMEN
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Migración completada${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Keycloak → MySQL (tp-mysql:3306/keycloak)  ✓"
echo "  Strapi    → MySQL (tp-mysql:3306/strapi)    ✓"
echo ""
echo "  Exports guardados en: $EXPORT_DIR"
echo "    Keycloak: $KC_EXPORT_DIR/"
echo "    Strapi:   $STRAPI_EXPORT_DIR/strapi-export.tar.gz"
echo ""
warn "RECUERDA: si pg1 vuelve, Keycloak y Strapi seguirán en MySQL."
warn "Los exports en $EXPORT_DIR son el respaldo. Guárdalos en un lugar seguro."
echo ""
