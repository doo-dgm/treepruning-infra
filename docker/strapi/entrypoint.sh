#!/bin/sh
# docker/strapi/entrypoint.sh
#
# Prueba pg1 al arrancar. Si está disponible usa PostgreSQL;
# si no, cae a MySQL. Mismo patrón que DataSourceFallbackPostProcessor del backend.
#
# Variables requeridas en el contenedor:
#   POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD
#   MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD
#
# Usa /bin/sh (no bash) porque node:20-alpine solo trae ash/sh.

PREFIX="[Strapi-failover]"
PG_HOST="${POSTGRES_HOST:-pg1}"
PG_PORT="${POSTGRES_PORT:-5432}"
MY_HOST="${MYSQL_HOST:-tp-mysql}"
MY_PORT="${MYSQL_PORT:-3306}"

echo "$PREFIX Sondeando PostgreSQL en $PG_HOST:$PG_PORT ..."

# node:20-alpine trae busybox nc. Usamos -z (port scan) con -w 3 (timeout en segundos).
if nc -z -w 3 "$PG_HOST" "$PG_PORT" 2>/dev/null; then
    echo "$PREFIX PostgreSQL disponible — Strapi usará PostgreSQL."
    export DATABASE_CLIENT=postgres
    export DATABASE_HOST="$PG_HOST"
    export DATABASE_PORT="$PG_PORT"
    export DATABASE_USERNAME="$POSTGRES_USER"
    export DATABASE_PASSWORD="$POSTGRES_PASSWORD"
else
    echo "$PREFIX PostgreSQL NO disponible — Strapi usará MySQL (fallback)."
    export DATABASE_CLIENT=mysql
    export DATABASE_HOST="$MY_HOST"
    export DATABASE_PORT="$MY_PORT"
    export DATABASE_USERNAME="$MYSQL_USER"
    export DATABASE_PASSWORD="$MYSQL_PASSWORD"
fi

exec npm run develop
