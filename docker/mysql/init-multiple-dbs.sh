#!/bin/bash
# docker/mysql/init-multiple-dbs.sh
# Crea las bases de datos adicionales al primer arranque de MySQL.
# La BD principal (treepruning) ya es creada por MYSQL_DATABASE.
# Este script agrega keycloak y strapi para la replicación CDC.
set -e

echo ">>> Creando bases de datos adicionales en MySQL..."

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS keycloak
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    CREATE DATABASE IF NOT EXISTS strapi
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    GRANT ALL PRIVILEGES ON keycloak.* TO '${MYSQL_USER}'@'%';
    GRANT ALL PRIVILEGES ON strapi.*   TO '${MYSQL_USER}'@'%';

    FLUSH PRIVILEGES;
EOSQL

echo ">>> Bases de datos creadas: keycloak, strapi (treepruning ya existía)"
