#!/bin/bash
# docker/postgres/init-multiple-dbs.sh
# Crea las bases de datos adicionales al primer arranque de PostgreSQL
set -e

echo ">>> Creando bases de datos adicionales..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  CREATE DATABASE kong;
  CREATE DATABASE keycloak;
  CREATE DATABASE strapi;
  CREATE DATABASE sonarqube;

  GRANT ALL PRIVILEGES ON DATABASE kong       TO $POSTGRES_USER;
  GRANT ALL PRIVILEGES ON DATABASE keycloak   TO $POSTGRES_USER;
  GRANT ALL PRIVILEGES ON DATABASE strapi     TO $POSTGRES_USER;
  GRANT ALL PRIVILEGES ON DATABASE sonarqube  TO $POSTGRES_USER;
EOSQL

echo ">>> Bases de datos creadas: kong, keycloak, strapi, sonarqube"
