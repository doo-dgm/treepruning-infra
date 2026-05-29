#!/bin/bash
# =============================================================================
# pgdump-to-mysql.sh
#
# Exporta una base de datos PostgreSQL como INSERTs y los importa en MySQL.
#
# USO:
#   infisical run --env=prod --projectId=<ID> -- \
#     bash docker/scripts/pgdump-to-mysql.sh <pg_database> <mysql_database>
#
# EJEMPLOS:
#   bash docker/scripts/pgdump-to-mysql.sh keycloak keycloak
#   bash docker/scripts/pgdump-to-mysql.sh strapi   strapi
# =============================================================================
set -euo pipefail

PG_DB="${1:-}"
MY_DB="${2:-}"

if [[ -z "$PG_DB" || -z "$MY_DB" ]]; then
    echo "Uso: bash $0 <pg_database> <mysql_database>"
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
# STEP 2: exportar desde pg1 y transformar a dialecto MySQL
# =============================================================================
log "Exportando $PG_DB desde pg1 con pg_dump --inserts ..."

# Cabecera: printf garantiza newlines reales (no depende de sed ni de la versión del SO)
printf 'SET FOREIGN_KEY_CHECKS=0;\nSET NAMES utf8mb4;\n\n' > "$OUT_FILE"

# pg_dump + transformaciones en pipeline
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pg1 \
    pg_dump \
        --username="$POSTGRES_USER" \
        --host=localhost \
        --dbname="$PG_DB" \
        --data-only \
        --inserts \
        --no-owner \
        --no-privileges \
        --no-comments \
    2>/dev/null \
| sed \
    -e '/^SET /d' \
    -e '/^\\connect/d' \
    -e '/^SELECT pg_catalog/d' \
    -e '/^ALTER SEQUENCE/d' \
    -e '/^CREATE SEQUENCE/d' \
    -e '/^SELECT setval/d' \
    -e '/^COPY /d' \
    -e '/^\\/d' \
    -e '/^--/d' \
    -e '/^$/d' \
    -e 's/public\.//g' \
    -e 's/"public"\.//g' \
    -e "s/'true'/1/g" \
    -e "s/'false'/0/g" \
| sed -E \
    -e 's/::[a-zA-Z_ ]+(\[\])?//g' \
    -e "s/\btrue\b/1/g" \
    -e "s/\bfalse\b/0/g" \
    -e 's/"([^"]+)"/`\1`/g' \
| awk '/^INSERT INTO [A-Za-z_]/{n=index($0," INTO ")+6;m=index(substr($0,n)," ")-1;tbl=substr($0,n,m);rest=substr($0,n+m);print "INSERT INTO " toupper(tbl) rest;next}1' \
>> "$OUT_FILE"

# Pie
printf '\nSET FOREIGN_KEY_CHECKS=1;\n' >> "$OUT_FILE"

LINES=$(wc -l < "$OUT_FILE")
log "SQL generado en: $OUT_FILE ($LINES líneas)"

# Verificar que hay contenido útil (más que solo el header + footer)
if [[ "$LINES" -lt 5 ]]; then
    error "El archivo SQL tiene muy pocas líneas ($LINES). ¿La base $PG_DB tiene datos?"
    exit 1
fi

# Mostrar primeras líneas para confirmar que el formato es correcto
log "Tablas existentes en tp-mysql/$MY_DB:"
docker exec \
    -e _PG2MY_PWD="$MYSQL_PASSWORD" \
    -e _PG2MY_USER="$MYSQL_USER" \
    -e _PG2MY_DB="$MY_DB" \
    tp-mysql \
    bash -c 'mysql --user="$_PG2MY_USER" --password="$_PG2MY_PWD" --database="$_PG2MY_DB" -e "SHOW TABLES;" 2>/dev/null' \
    | head -20

log "Primeras 6 líneas del SQL generado (verificar UPPERCASE):"
head -6 "$OUT_FILE"

# =============================================================================
# STEP 3: copiar SQL al contenedor y ejecutar desde adentro
# =============================================================================
# Copiar el archivo SQL al contenedor evita stdin redirect + caracteres especiales
log "Copiando SQL a tp-mysql:/tmp/import_${PG_DB}.sql ..."
docker cp "$OUT_FILE" "tp-mysql:/tmp/import_${PG_DB}.sql"

log "Importando en tp-mysql/$MY_DB ..."
warn "Esto puede tardar varios minutos."

# Pasar usuario y contraseña como variables de entorno al contenedor.
# La contraseña puede contener cualquier caracter especial — docker exec -e
# la pasa como valor de entorno sin interpretación de shell adicional.
# Dentro del contenedor, bash -c con comillas simples expande $VAR del entorno
# del contenedor, no del host — completamente seguro para contraseñas complejas.
docker exec \
    -e _PG2MY_PWD="$MYSQL_PASSWORD" \
    -e _PG2MY_USER="$MYSQL_USER" \
    -e _PG2MY_DB="$MY_DB" \
    -e _PG2MY_FILE="/tmp/import_${PG_DB}.sql" \
    tp-mysql \
    bash -c 'mysql --user="$_PG2MY_USER" --password="$_PG2MY_PWD" \
                   --database="$_PG2MY_DB" \
                   --default-character-set=utf8mb4 \
                   < "$_PG2MY_FILE"' \
    && log "✓ Importación completada en $MY_DB." \
    || { error "✗ Error al importar."; exit 1; }

# Limpiar el archivo temporal del contenedor
docker exec tp-mysql rm -f "/tmp/import_${PG_DB}.sql"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Migración $PG_DB → MySQL/$MY_DB completada${NC}"
echo -e "${GREEN}============================================================${NC}"
echo "  SQL guardado en: $OUT_FILE"
echo ""
