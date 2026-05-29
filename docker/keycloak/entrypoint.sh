#!/bin/bash
# docker/keycloak/entrypoint.sh
#
# Prueba pg1 al arrancar. Si está disponible usa PostgreSQL;
# si no, cae a MySQL. Mismo patrón que DataSourceFallbackPostProcessor del backend.
#
# Variables requeridas en el contenedor:
#   POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD
#   MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD

set -e

PREFIX="[KC-failover]"
PG_HOST="${POSTGRES_HOST:-pg1}"
PG_PORT="${POSTGRES_PORT:-5432}"
MY_HOST="${MYSQL_HOST:-tp-mysql}"
MY_PORT="${MYSQL_PORT:-3306}"

echo "$PREFIX Sondeando PostgreSQL en $PG_HOST:$PG_PORT ..."

# Usa /dev/tcp de bash (built-in, no requiere nc ni curl).
# timeout 3: evita colgar si pg1 acepta TCP pero no responde.
if timeout 3 bash -c "exec 3<>/dev/tcp/$PG_HOST/$PG_PORT" 2>/dev/null; then
    echo "$PREFIX PostgreSQL disponible — Keycloak usará PostgreSQL."
    export KC_DB=postgres
    export KC_DB_URL="jdbc:postgresql://${PG_HOST}:${PG_PORT}/keycloak"
    export KC_DB_USERNAME="$POSTGRES_USER"
    export KC_DB_PASSWORD="$POSTGRES_PASSWORD"
else
    echo "$PREFIX PostgreSQL NO disponible — Keycloak usará MySQL (fallback)."
    export KC_DB=mysql
    export KC_DB_URL="jdbc:mysql://${MY_HOST}:${MY_PORT}/keycloak?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
    export KC_DB_USERNAME="$MYSQL_USER"
    export KC_DB_PASSWORD="$MYSQL_PASSWORD"
fi

exec /opt/keycloak/bin/kc.sh start-dev
