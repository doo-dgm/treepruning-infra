-- =============================================================================
-- docker/mysql/init-treepruning-extra.sql
--
-- Tablas de treepruning que NO tienen entidad JPA y por tanto Hibernate
-- no crea automáticamente. Se ejecuta al primer arranque de MySQL.
-- Las tablas gestionadas por Hibernate (country, person, tree, etc.)
-- NO están aquí — las crea Hibernate con ddl-auto.
-- =============================================================================

USE treepruning;

CREATE TABLE IF NOT EXISTS tool (
    id          CHAR(36)     NOT NULL PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS administrator (
    id               CHAR(36)     NOT NULL PRIMARY KEY,
    username         VARCHAR(100) NOT NULL UNIQUE,
    email            VARCHAR(255) NOT NULL,
    email_confirmed  TINYINT(1)   NOT NULL,
    phone            VARCHAR(50)  NOT NULL,
    phone_confirmed  TINYINT(1)   NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS operator (
    id           CHAR(36) NOT NULL PRIMARY KEY,
    person_id    CHAR(36) NOT NULL,
    quadrille_id CHAR(36)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pruning_tool (
    pruning_id CHAR(36) NOT NULL,
    tool_id    CHAR(36) NOT NULL,
    quantity   INT      NOT NULL DEFAULT 1,
    PRIMARY KEY (pruning_id, tool_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
