-- =============================================================================
-- TreePruning — inicialización de esquema y datos base
-- Se ejecuta automáticamente al crear el contenedor pg1 por primera vez.
-- Postgres Docker corre todos los archivos de /docker-entrypoint-initdb.d/
-- en orden alfabético; este archivo corre DESPUÉS de init-multiple-dbs.sh.
-- =============================================================================

-- =============================================================================
-- ESQUEMA
-- =============================================================================
DROP SCHEMA IF EXISTS treepruning CASCADE;
CREATE SCHEMA treepruning;
GRANT ALL ON SCHEMA treepruning TO postgres;

-- =============================================================================
-- TABLAS BASE — catálogos y geografía
-- =============================================================================
CREATE TABLE treepruning.country (
    id   UUID         PRIMARY KEY,
    name VARCHAR(150) NOT NULL
);

CREATE TABLE treepruning.state (
    id         UUID         PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    country_id UUID         NOT NULL,
    FOREIGN KEY (country_id) REFERENCES treepruning.country(id)
);

CREATE TABLE treepruning.municipality (
    id       UUID         PRIMARY KEY,
    name     VARCHAR(150) NOT NULL,
    state_id UUID         NOT NULL,
    FOREIGN KEY (state_id) REFERENCES treepruning.state(id)
);

CREATE TABLE treepruning.sector (
    id              UUID         PRIMARY KEY,
    name            VARCHAR(150) NOT NULL,
    municipality_id UUID,
    FOREIGN KEY (municipality_id) REFERENCES treepruning.municipality(id) ON DELETE SET NULL
);

CREATE TABLE treepruning.family (
    id              UUID         PRIMARY KEY,
    scientific_name VARCHAR(200),
    common_name     VARCHAR(200)
);

CREATE TABLE treepruning.type (
    id   UUID         PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE treepruning.risk (
    id   UUID         PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE treepruning.status (
    id   UUID         PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE treepruning.tool (
    id          UUID         PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    description TEXT
);

CREATE TABLE treepruning.document (
    id   UUID         PRIMARY KEY,
    name VARCHAR(150),
    code VARCHAR(100)
);

-- =============================================================================
-- TABLAS DE DOMINIO — personas, cuadrillas y árboles
-- =============================================================================
CREATE TABLE treepruning.person (
    id               UUID         PRIMARY KEY,
    first_name       VARCHAR(120) NOT NULL,
    middle_name      VARCHAR(120),
    surname          VARCHAR(120),
    second_surname   VARCHAR(120),
    document_id      UUID         NOT NULL,
    document_number  VARCHAR(100),
    birth_date       DATE,
    address          TEXT,
    email            VARCHAR(255),
    email_confirmed  BOOLEAN      NOT NULL,
    phone            VARCHAR(50),
    phone_confirmed  BOOLEAN      NOT NULL,
    age              INT,
    FOREIGN KEY (document_id) REFERENCES treepruning.document(id)
);

CREATE TABLE treepruning.manager (
    id        UUID PRIMARY KEY,
    person_id UUID NOT NULL,
    FOREIGN KEY (person_id) REFERENCES treepruning.person(id) ON DELETE CASCADE
);

CREATE TABLE treepruning.quadrille (
    id             UUID         PRIMARY KEY,
    quadrille_name VARCHAR(150),
    manager_id     UUID,
    FOREIGN KEY (manager_id) REFERENCES treepruning.manager(id) ON DELETE SET NULL
);

CREATE TABLE treepruning.administrator (
    id               UUID         PRIMARY KEY,
    username         VARCHAR(100) UNIQUE NOT NULL,
    email            VARCHAR(255) NOT NULL,
    email_confirmed  BOOLEAN      NOT NULL,
    phone            VARCHAR(50)  NOT NULL,
    phone_confirmed  BOOLEAN      NOT NULL
);

CREATE TABLE treepruning.operator (
    id           UUID PRIMARY KEY,
    person_id    UUID NOT NULL,
    quadrille_id UUID,
    FOREIGN KEY (person_id)    REFERENCES treepruning.person(id)    ON DELETE CASCADE,
    FOREIGN KEY (quadrille_id) REFERENCES treepruning.quadrille(id) ON DELETE SET NULL
);

CREATE TABLE treepruning.programming (
    id               UUID PRIMARY KEY,
    initial_date     DATE,
    frequency_months INT,
    amount           INT  NOT NULL
);

CREATE TABLE treepruning.tree (
    id             UUID           PRIMARY KEY,
    family_id      UUID,
    longitude      NUMERIC(10, 6),
    latitude       NUMERIC(10, 6),
    sector_id      UUID,
    programming_id UUID,
    FOREIGN KEY (family_id)      REFERENCES treepruning.family(id)      ON DELETE SET NULL,
    FOREIGN KEY (sector_id)      REFERENCES treepruning.sector(id)      ON DELETE SET NULL,
    FOREIGN KEY (programming_id) REFERENCES treepruning.programming(id) ON DELETE SET NULL
);

-- =============================================================================
-- TABLAS DE DOMINIO — PQR y podas
-- =============================================================================
CREATE TABLE treepruning.pqr (
    id                      UUID PRIMARY KEY,
    date                    DATE,
    status_id               UUID,
    person_id               UUID,
    sector_id               UUID,
    risk_id                 UUID,
    photographic_record_path TEXT,
    FOREIGN KEY (person_id) REFERENCES treepruning.person(id) ON DELETE SET NULL,
    FOREIGN KEY (sector_id) REFERENCES treepruning.sector(id) ON DELETE SET NULL
);

CREATE TABLE treepruning.pruning (
    id                      UUID  PRIMARY KEY,
    status_id               UUID  NOT NULL,
    planned_date            DATE,
    executed_date           DATE,
    tree_id                 UUID  NOT NULL,
    quadrille_id            UUID  NOT NULL,
    type_id                 UUID  NOT NULL,
    pqr_id                  UUID,
    photographic_report_path TEXT,
    observations            TEXT,
    FOREIGN KEY (tree_id) REFERENCES treepruning.tree(id) ON DELETE CASCADE,
    FOREIGN KEY (type_id) REFERENCES treepruning.type(id)
);

CREATE TABLE treepruning.pruning_tool (
    pruning_id UUID NOT NULL,
    tool_id    UUID NOT NULL,
    quantity   INT  DEFAULT 1,
    PRIMARY KEY (pruning_id, tool_id),
    FOREIGN KEY (pruning_id) REFERENCES treepruning.pruning(id) ON DELETE CASCADE,
    FOREIGN KEY (tool_id)    REFERENCES treepruning.tool(id)
);

-- =============================================================================
-- TABLAS DE NOTIFICACIONES (FCM)
-- =============================================================================
CREATE TABLE treepruning.notification_tokens (
    id         UUID         PRIMARY KEY,
    user_id    UUID         NOT NULL,
    fcm_token  TEXT         NOT NULL,
    language   VARCHAR(5)   NOT NULL DEFAULT 'es',
    created_at TIMESTAMP    NOT NULL DEFAULT now(),
    updated_at TIMESTAMP,
    active     BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE treepruning.notification_history (
    id         UUID         PRIMARY KEY,
    user_id    UUID         NOT NULL,
    title      VARCHAR(255),
    body       TEXT,
    pruning_id UUID,
    type       VARCHAR(100),
    sent_at    TIMESTAMP    NOT NULL DEFAULT now(),
    success    BOOLEAN      NOT NULL DEFAULT TRUE
);

-- =============================================================================
-- ÍNDICES
-- =============================================================================
CREATE INDEX idx_tree_family          ON treepruning.tree(family_id);
CREATE INDEX idx_tree_programming     ON treepruning.tree(programming_id);
CREATE INDEX idx_pruning_tree         ON treepruning.pruning(tree_id);
CREATE INDEX idx_person_docnum        ON treepruning.person(document_number);
CREATE INDEX idx_sector_municipality  ON treepruning.sector(municipality_id);
CREATE INDEX idx_notif_token_user     ON treepruning.notification_tokens(user_id);
CREATE INDEX idx_notif_token_fcm      ON treepruning.notification_tokens(fcm_token);
CREATE INDEX idx_notif_history_user   ON treepruning.notification_history(user_id);
CREATE INDEX idx_notif_history_pruning ON treepruning.notification_history(pruning_id);

-- =============================================================================
-- DATOS BASE
-- =============================================================================

-- Tipos de documento
INSERT INTO treepruning.document (id, name, code) VALUES
('00000000-0000-0000-0000-000000000001', 'Cédula de Ciudadanía',              'CC'),
('00000000-0000-0000-0000-000000000002', 'Número de Identificación Tributaria','NIT');

-- Familias arbóreas
INSERT INTO treepruning.family (id, scientific_name, common_name) VALUES
('00000000-0000-0000-0000-000000000003', 'Tabebuia rosea', 'Roble Rosado'),
('00000000-0000-0000-0000-000000000004', 'Pinus patula',   'Pino Pátula');

-- Tipos de poda
-- 'Poda Preventiva' es el tipo asignado automáticamente por el interactor
-- al programar una poda preventiva (parámetro Strapi: podas.tipo-creacion-preventiva).
INSERT INTO treepruning.type (id, name) VALUES
('00000000-0000-0000-0000-000000000005', 'Poda Sanitaria'),
('00000000-0000-0000-0000-000000000006', 'Poda de Formación'),
('00000000-0000-0000-0000-000000000028', 'Poda Preventiva');

-- Riesgos
INSERT INTO treepruning.risk (id, name) VALUES
('00000000-0000-0000-0000-000000000007', 'Alto Riesgo de Caída'),
('00000000-0000-0000-0000-000000000008', 'Interferencia con redes eléctricas');

-- Estados
-- 'Planeada' es el estado inicial de una poda recién programada
-- (parámetro Strapi: podas.estado-creacion-default).
INSERT INTO treepruning.status (id, name) VALUES
('00000000-0000-0000-0000-000000000009', 'Pendiente'),
('00000000-0000-0000-0000-000000000010', 'Ejecutado'),
('00000000-0000-0000-0000-000000000029', 'Planeada');

-- Herramientas
INSERT INTO treepruning.tool (id, name, description) VALUES
('00000000-0000-0000-0000-000000000011', 'Motosierra Stihl MS 382',  'Motosierra de alta potencia para troncos gruesos'),
('00000000-0000-0000-0000-000000000012', 'Tijeras de Poda Altura',   'Tijeras telescópicas para ramas altas');

-- Administrador inicial
INSERT INTO treepruning.administrator (id, username, email, email_confirmed, phone, phone_confirmed) VALUES
('00000000-0000-0000-0000-000000000013', 'admin_main', 'admin@treepruning.com', TRUE, '+573001234567', TRUE);

-- Geografía: Colombia → Antioquia → Medellín → El Poblado
INSERT INTO treepruning.country (id, name) VALUES
('00000000-0000-0000-0000-000000000014', 'Colombia');

INSERT INTO treepruning.state (id, name, country_id) VALUES
('00000000-0000-0000-0000-000000000015', 'Antioquia', '00000000-0000-0000-0000-000000000014');

INSERT INTO treepruning.municipality (id, name, state_id) VALUES
('00000000-0000-0000-0000-000000000016', 'Medellín', '00000000-0000-0000-0000-000000000015');

INSERT INTO treepruning.sector (id, name, municipality_id) VALUES
('00000000-0000-0000-0000-000000000017', 'El Poblado', '00000000-0000-0000-0000-000000000016');

-- Manager
INSERT INTO treepruning.person (id, first_name, middle_name, surname, second_surname, document_id,
    document_number, email, email_confirmed, phone, phone_confirmed, age) VALUES
('00000000-0000-0000-0000-000000000018', 'Carlos', 'Andrés', 'Gómez', 'López',
    '00000000-0000-0000-0000-000000000001', '1017123456',
    'carlos.gomez@empresa.com', TRUE, '3101112233', TRUE, 45);

INSERT INTO treepruning.manager (id, person_id) VALUES
('00000000-0000-0000-0000-000000000019', '00000000-0000-0000-0000-000000000018');

-- Cuadrilla
INSERT INTO treepruning.quadrille (id, quadrille_name, manager_id) VALUES
('00000000-0000-0000-0000-000000000020', 'Cuadrilla Norte - Alpha',
    '00000000-0000-0000-0000-000000000019');

-- Operario
INSERT INTO treepruning.person (id, first_name, middle_name, surname, second_surname, document_id,
    document_number, email, email_confirmed, phone, phone_confirmed, age) VALUES
('00000000-0000-0000-0000-000000000021', 'Juan', 'David', 'Pérez', 'Ruiz',
    '00000000-0000-0000-0000-000000000001', '1020987654',
    'juan.perez@empresa.com', TRUE, '3114445566', TRUE, 28);

INSERT INTO treepruning.operator (id, person_id, quadrille_id) VALUES
('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000020');

-- Ciudadano
INSERT INTO treepruning.person (id, first_name, middle_name, surname, second_surname, document_id,
    document_number, email, email_confirmed, phone, phone_confirmed, age) VALUES
('00000000-0000-0000-0000-000000000023', 'Maria', 'Fernanda', 'Torres', 'Diaz',
    '00000000-0000-0000-0000-000000000001', '43123456',
    'maria.torres@gmail.com', TRUE, '3009998877', TRUE, 34);

-- Programación y árbol de ejemplo
INSERT INTO treepruning.programming (id, initial_date, frequency_months, amount) VALUES
('00000000-0000-0000-0000-000000000024', '2023-01-15', 6, 2);

INSERT INTO treepruning.tree (id, family_id, longitude, latitude, sector_id, programming_id) VALUES
('00000000-0000-0000-0000-000000000025',
    '00000000-0000-0000-0000-000000000003',
    -75.5678, 6.2345,
    '00000000-0000-0000-0000-000000000017',
    '00000000-0000-0000-0000-000000000024');

-- PQR de ejemplo
INSERT INTO treepruning.pqr (id, date, status_id, person_id, sector_id, risk_id, photographic_record_path) VALUES
('00000000-0000-0000-0000-000000000026',
    CURRENT_DATE,
    '00000000-0000-0000-0000-000000000009',
    '00000000-0000-0000-0000-000000000023',
    '00000000-0000-0000-0000-000000000017',
    '00000000-0000-0000-0000-000000000007',
    '/uploads/pqr/foto_rama_caida.jpg');

-- Poda de ejemplo
INSERT INTO treepruning.pruning (id, status_id, planned_date, executed_date, tree_id,
    quadrille_id, type_id, pqr_id, observations) VALUES
('00000000-0000-0000-0000-000000000027',
    '00000000-0000-0000-0000-000000000010',
    '2023-10-01', '2023-10-02',
    '00000000-0000-0000-0000-000000000025',
    '00000000-0000-0000-0000-000000000020',
    '00000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-000000000026',
    'Se realizó corte de ramas secas que interferían con cableado.');

-- Herramientas de la poda de ejemplo
INSERT INTO treepruning.pruning_tool (pruning_id, tool_id, quantity) VALUES
('00000000-0000-0000-0000-000000000027', '00000000-0000-0000-0000-000000000011', 1),
('00000000-0000-0000-0000-000000000027', '00000000-0000-0000-0000-000000000012', 2);
