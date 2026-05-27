-- =============================================================================
-- SQL Server — esquema treepruning (equivalente al init-treepruning.sql de PG)
-- Ejecutar en la base de datos 'treepruning':
--   sqlcmd -S localhost -U sa -P <PASSWORD> -d treepruning -i init-treepruning.sql
-- Todas las tablas van en el esquema dbo (default de SQL Server).
-- =============================================================================

USE treepruning;
GO

-- =============================================================================
-- TABLAS BASE
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'country')
CREATE TABLE dbo.country (
    id   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name NVARCHAR(150)    NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'state')
CREATE TABLE dbo.state (
    id         UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name       NVARCHAR(150)    NOT NULL,
    country_id UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT fk_state_country FOREIGN KEY (country_id) REFERENCES dbo.country(id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'municipality')
CREATE TABLE dbo.municipality (
    id       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name     NVARCHAR(150)    NOT NULL,
    state_id UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT fk_municipality_state FOREIGN KEY (state_id) REFERENCES dbo.state(id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'sector')
CREATE TABLE dbo.sector (
    id              UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name            NVARCHAR(150)    NOT NULL,
    municipality_id UNIQUEIDENTIFIER NULL,
    CONSTRAINT fk_sector_municipality FOREIGN KEY (municipality_id)
        REFERENCES dbo.municipality(id) ON DELETE SET NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'family')
CREATE TABLE dbo.family (
    id              UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    scientific_name NVARCHAR(200)    NULL,
    common_name     NVARCHAR(200)    NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'type')
CREATE TABLE dbo.type (
    id   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name NVARCHAR(100)    NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'risk')
CREATE TABLE dbo.risk (
    id   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name NVARCHAR(100)    NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'status')
CREATE TABLE dbo.status (
    id   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name NVARCHAR(100)    NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'tool')
CREATE TABLE dbo.tool (
    id          UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name        NVARCHAR(150)    NOT NULL,
    description NVARCHAR(MAX)    NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'document')
CREATE TABLE dbo.document (
    id   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    name NVARCHAR(150)    NULL,
    code NVARCHAR(100)    NULL
);
GO

-- =============================================================================
-- PERSONAS, ROLES Y CUADRILLAS
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'person')
CREATE TABLE dbo.person (
    id               UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    first_name       NVARCHAR(120)    NOT NULL,
    middle_name      NVARCHAR(120)    NULL,
    surname          NVARCHAR(120)    NULL,
    second_surname   NVARCHAR(120)    NULL,
    document_id      UNIQUEIDENTIFIER NOT NULL,
    document_number  NVARCHAR(100)    NULL,
    birth_date       DATE             NULL,
    address          NVARCHAR(MAX)    NULL,
    email            NVARCHAR(255)    NULL,
    email_confirmed  BIT              NOT NULL,
    phone            NVARCHAR(50)     NULL,
    phone_confirmed  BIT              NOT NULL,
    age              INT              NULL,
    CONSTRAINT fk_person_document FOREIGN KEY (document_id)
        REFERENCES dbo.document(id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'manager')
CREATE TABLE dbo.manager (
    id        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    person_id UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT fk_manager_person FOREIGN KEY (person_id)
        REFERENCES dbo.person(id) ON DELETE CASCADE
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'quadrille')
CREATE TABLE dbo.quadrille (
    id             UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    quadrille_name NVARCHAR(150)    NULL,
    manager_id     UNIQUEIDENTIFIER NULL,
    CONSTRAINT fk_quadrille_manager FOREIGN KEY (manager_id)
        REFERENCES dbo.manager(id) ON DELETE SET NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'administrator')
CREATE TABLE dbo.administrator (
    id              UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    username        NVARCHAR(100)    NOT NULL UNIQUE,
    email           NVARCHAR(255)    NOT NULL,
    email_confirmed BIT              NOT NULL,
    phone           NVARCHAR(50)     NOT NULL,
    phone_confirmed BIT              NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'operator')
CREATE TABLE dbo.operator (
    id           UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    person_id    UNIQUEIDENTIFIER NOT NULL,
    quadrille_id UNIQUEIDENTIFIER NULL,
    CONSTRAINT fk_operator_person    FOREIGN KEY (person_id)
        REFERENCES dbo.person(id)    ON DELETE CASCADE,
    CONSTRAINT fk_operator_quadrille FOREIGN KEY (quadrille_id)
        REFERENCES dbo.quadrille(id) ON DELETE SET NULL
);
GO

-- =============================================================================
-- ÁRBOLES Y PROGRAMACIÓN
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'programming')
CREATE TABLE dbo.programming (
    id               UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    initial_date     DATE             NULL,
    frequency_months INT              NULL,
    amount           INT              NOT NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'tree')
CREATE TABLE dbo.tree (
    id             UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    family_id      UNIQUEIDENTIFIER NULL,
    longitude      DECIMAL(10, 6)   NULL,
    latitude       DECIMAL(10, 6)   NULL,
    sector_id      UNIQUEIDENTIFIER NULL,
    programming_id UNIQUEIDENTIFIER NULL,
    CONSTRAINT fk_tree_family      FOREIGN KEY (family_id)
        REFERENCES dbo.family(id)      ON DELETE SET NULL,
    CONSTRAINT fk_tree_sector      FOREIGN KEY (sector_id)
        REFERENCES dbo.sector(id)      ON DELETE SET NULL,
    CONSTRAINT fk_tree_programming FOREIGN KEY (programming_id)
        REFERENCES dbo.programming(id) ON DELETE SET NULL
);
GO

-- =============================================================================
-- PQR Y PODAS
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pqr')
CREATE TABLE dbo.pqr (
    id                       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    date                     DATE             NULL,
    status_id                UNIQUEIDENTIFIER NULL,
    person_id                UNIQUEIDENTIFIER NULL,
    sector_id                UNIQUEIDENTIFIER NULL,
    risk_id                  UNIQUEIDENTIFIER NULL,
    photographic_record_path NVARCHAR(MAX)    NULL,
    CONSTRAINT fk_pqr_person FOREIGN KEY (person_id)
        REFERENCES dbo.person(id) ON DELETE SET NULL,
    CONSTRAINT fk_pqr_sector FOREIGN KEY (sector_id)
        REFERENCES dbo.sector(id) ON DELETE SET NULL
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pruning')
CREATE TABLE dbo.pruning (
    id                       UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    status_id                UNIQUEIDENTIFIER NOT NULL,
    planned_date             DATE             NULL,
    executed_date            DATE             NULL,
    tree_id                  UNIQUEIDENTIFIER NOT NULL,
    quadrille_id             UNIQUEIDENTIFIER NOT NULL,
    type_id                  UNIQUEIDENTIFIER NOT NULL,
    pqr_id                   UNIQUEIDENTIFIER NULL,
    photographic_report_path NVARCHAR(MAX)    NULL,
    observations             NVARCHAR(MAX)    NULL,
    CONSTRAINT fk_pruning_tree FOREIGN KEY (tree_id)
        REFERENCES dbo.tree(id) ON DELETE CASCADE,
    CONSTRAINT fk_pruning_type FOREIGN KEY (type_id)
        REFERENCES dbo.type(id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pruning_tool')
CREATE TABLE dbo.pruning_tool (
    pruning_id UNIQUEIDENTIFIER NOT NULL,
    tool_id    UNIQUEIDENTIFIER NOT NULL,
    quantity   INT              DEFAULT 1,
    CONSTRAINT pk_pruning_tool PRIMARY KEY (pruning_id, tool_id),
    CONSTRAINT fk_pt_pruning FOREIGN KEY (pruning_id)
        REFERENCES dbo.pruning(id) ON DELETE CASCADE,
    CONSTRAINT fk_pt_tool    FOREIGN KEY (tool_id)
        REFERENCES dbo.tool(id)
);
GO

-- =============================================================================
-- NOTIFICACIONES
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notification_tokens')
CREATE TABLE dbo.notification_tokens (
    id         UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER NOT NULL,
    fcm_token  NVARCHAR(MAX)    NOT NULL,
    language   NVARCHAR(5)      NOT NULL DEFAULT 'es',
    created_at DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2        NULL,
    active     BIT              NOT NULL DEFAULT 1
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notification_history')
CREATE TABLE dbo.notification_history (
    id         UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER NOT NULL,
    title      NVARCHAR(255)    NULL,
    body       NVARCHAR(MAX)    NULL,
    pruning_id UNIQUEIDENTIFIER NULL,
    type       NVARCHAR(100)    NULL,
    sent_at    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
    success    BIT              NOT NULL DEFAULT 1
);
GO

-- =============================================================================
-- ÍNDICES
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_tree_family')
    CREATE INDEX idx_tree_family          ON dbo.tree(family_id);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_tree_programming')
    CREATE INDEX idx_tree_programming     ON dbo.tree(programming_id);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_pruning_tree')
    CREATE INDEX idx_pruning_tree         ON dbo.pruning(tree_id);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_person_docnum')
    CREATE INDEX idx_person_docnum        ON dbo.person(document_number);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_sector_municipality')
    CREATE INDEX idx_sector_municipality  ON dbo.sector(municipality_id);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_notif_token_user')
    CREATE INDEX idx_notif_token_user     ON dbo.notification_tokens(user_id);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_notif_history_user')
    CREATE INDEX idx_notif_history_user   ON dbo.notification_history(user_id);
GO

-- =============================================================================
-- DATOS BASE (seed)
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM dbo.document)
BEGIN
    INSERT INTO dbo.document (id, name, code) VALUES
    ('00000000-0000-0000-0000-000000000001', N'Cédula de Ciudadanía',               'CC'),
    ('00000000-0000-0000-0000-000000000002', N'Número de Identificación Tributaria', 'NIT');

    INSERT INTO dbo.family (id, scientific_name, common_name) VALUES
    ('00000000-0000-0000-0000-000000000003', 'Tabebuia rosea', N'Roble Rosado'),
    ('00000000-0000-0000-0000-000000000004', 'Pinus patula',   N'Pino Pátula');

    INSERT INTO dbo.type (id, name) VALUES
    ('00000000-0000-0000-0000-000000000005', N'Poda Sanitaria'),
    ('00000000-0000-0000-0000-000000000006', N'Poda de Formación'),
    ('00000000-0000-0000-0000-000000000028', N'Poda Preventiva');

    INSERT INTO dbo.risk (id, name) VALUES
    ('00000000-0000-0000-0000-000000000007', N'Alto Riesgo de Caída'),
    ('00000000-0000-0000-0000-000000000008', N'Interferencia con redes eléctricas');

    INSERT INTO dbo.status (id, name) VALUES
    ('00000000-0000-0000-0000-000000000009', N'Pendiente'),
    ('00000000-0000-0000-0000-000000000010', N'Ejecutado'),
    ('00000000-0000-0000-0000-000000000029', N'Planeada');

    INSERT INTO dbo.tool (id, name, description) VALUES
    ('00000000-0000-0000-0000-000000000011', N'Motosierra Stihl MS 382', N'Motosierra de alta potencia para troncos gruesos'),
    ('00000000-0000-0000-0000-000000000012', N'Tijeras de Poda Altura',  N'Tijeras telescópicas para ramas altas');

    INSERT INTO dbo.administrator (id, username, email, email_confirmed, phone, phone_confirmed) VALUES
    ('00000000-0000-0000-0000-000000000013', 'admin_main', 'admin@treepruning.com', 1, '+573001234567', 1);

    INSERT INTO dbo.country (id, name) VALUES
    ('00000000-0000-0000-0000-000000000014', 'Colombia');

    INSERT INTO dbo.state (id, name, country_id) VALUES
    ('00000000-0000-0000-0000-000000000015', 'Antioquia', '00000000-0000-0000-0000-000000000014');

    INSERT INTO dbo.municipality (id, name, state_id) VALUES
    ('00000000-0000-0000-0000-000000000016', N'Medellín', '00000000-0000-0000-0000-000000000015');

    INSERT INTO dbo.sector (id, name, municipality_id) VALUES
    ('00000000-0000-0000-0000-000000000017', 'El Poblado', '00000000-0000-0000-0000-000000000016');

    PRINT 'Datos base insertados correctamente.';
END
ELSE
    PRINT 'Datos base ya existen, se omite la inserción.';
GO
