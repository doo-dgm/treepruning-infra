#!/bin/bash
# =============================================================================
# pgdump-to-mysql.sh
#
# Exporta una base de datos PostgreSQL como INSERTs y los convierte al
# dialecto MySQL, listos para importar en tp-mysql.
#
# USO:
#   infisical run --env=prod --projectId=<ID> -- \
#     bash docker/scripts/pgdump-to-mysql.sh <pg_database> <mysql_database>
#
# EJEMPLOS:
#   bash pgdump-to-mysql.sh keycloak keycloak
#   bash pgdump-to-mysql.sh strapi   strapi
#
# PREREQUISITOS:
#   - pg1 corriendo y healthy
#   - tp-mysql corriendo y healthy
#   - Variables: POSTGRES_USER, POSTGRES_PASSWORD, MYSQL_USER, MYSQL_PASSWORD
# =============================================================================
set -euo pipefail

PG_DB="${1:-}"
MY_DB="${2:-}"

if [[ -z "$PG_DB" || -z "$MY_DB" ]]; then
    echo "Uso: bash $0 <pg_database> <mysql_database>"
    echo "  ej: bash $0 keycloak keycloak"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_FILE="$SCRIPT_DIR/migration-exports/${PG_DB}-mysql.sql"
mkdir -p "$(dirname "$OUT_FILE")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[pg→mysql]${NC} $*"; }
warn()  { echo -e "${YELLOW}[pg→mysql]${NC} $*"; }
error() { echo -e "${RED}[pg→mysql]${NC} $*" >&2; }

# =============================================================================
# STEP 1: verificar contenedores
# =============================================================================
for c in pg1 tp-mysql; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
    if [[ "$STATUS" != "running" ]]; then
        error "Contenedor $c no está corriendo (status: $STATUS). Abortando."
        exit 1
    fi
done

# =============================================================================
# STEP 2: pg_dump --inserts desde pg1
# =============================================================================
log "Exportando $PG_DB desde pg1 con pg_dump --inserts ..."

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pg1 \
    pg_dump \
        --username="$POSTGRES_USER" \
        --dbname="$PG_DB" \
        --data-only \
        --inserts \
        --no-owner \
        --no-privileges \
        --no-comments \
    2>/dev/null \
| \
# =============================================================================
# STEP 3: transformaciones PostgreSQL → MySQL
# =============================================================================
# Las transformaciones se aplican en pipeline con sed/awk:
#
# 1. Eliminar líneas que no tienen sentido en MySQL:
#    SET client_encoding, SET standard_conforming_strings, SELECT pg_catalog...
#    ALTER SEQUENCE, SELECT setval, COPY ... FROM stdin, \.
# 2. Quitar el schema "public." de los nombres de tabla
# 3. Convertir comillas dobles de identificadores a backticks
# 4. Convertir booleanos: 't'/'f' → 1/0 (PostgreSQL los serializa como char)
# 5. Convertir 'true'/'false' literales a 1/0
# 6. Eliminar casts de tipo (::text, ::character varying, ::uuid, etc.)
# 7. Reemplazar '' (empty string boolean) por NULL donde corresponda
# =============================================================================
sed \
    -e '/^SET /d' \
    -e '/^SELECT pg_catalog/d' \
    -e '/^ALTER SEQUENCE/d' \
    -e '/^CREATE SEQUENCE/d' \
    -e '/^SELECT setval/d' \
    -e '/^COPY /d' \
    -e '/^\\\./d' \
    -e '/^--/d' \
    -e '/^$/d' \
    -e "s/public\\.//g" \
    -e "s/\"public\"\.//g" \
    -e 's/::[a-zA-Z_ ]*\(\[[0-9]*\]\)\{0,1\}//g' \
    -e "s/'true'/1/g" \
    -e "s/'false'/0/g" \
    -e "s/\btrue\b/1/g" \
    -e "s/\bfalse\b/0/g" \
| \
# Convertir identificadores con comillas dobles a backticks (awk más seguro que sed para esto)
awk '{
    gsub(/"([^"]+)"/, function(m) {
        gsub(/^"|"$/, "", m)
        return "`" m "`"
    })
    print
}' \
| \
# Añadir cabecera MySQL y deshabilitar checks de FK durante la carga
awk 'BEGIN {
    print "SET FOREIGN_KEY_CHECKS=0;"
    print "SET NAMES utf8mb4;"
    print ""
}
{ print }
END {
    print ""
    print "SET FOREIGN_KEY_CHECKS=1;"
}' \
> "$OUT_FILE"

log "SQL generado en: $OUT_FILE"
log "Líneas: $(wc -l < "$OUT_FILE")"

# =============================================================================
# STEP 4: importar a MySQL
# =============================================================================
log "Importando en tp-mysql/$MY_DB ..."
warn "Esto puede tardar varios minutos dependiendo del volumen de datos."

docker exec -i tp-mysql \
    mysql \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --database="$MY_DB" \
        --default-character-set=utf8mb4 \
    < "$OUT_FILE" \
    && log "✓ Importación completada en $MY_DB." \
    || { error "✗ Error al importar. Revisa $OUT_FILE para ver las sentencias generadas."; exit 1; }

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Migración $PG_DB → MySQL/$MY_DB completada${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  SQL guardado en: $OUT_FILE  (cópialo si quieres repetir la carga)"
echo ""
