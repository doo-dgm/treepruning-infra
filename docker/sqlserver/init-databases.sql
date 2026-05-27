-- =============================================================================
-- SQL Server — creación de bases de datos para todos los servicios
-- Ejecutar como: sqlcmd -S localhost -U sa -P <PASSWORD> -i init-databases.sql
-- =============================================================================

-- keycloak
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'keycloak')
    CREATE DATABASE keycloak COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

-- strapi
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'strapi')
    CREATE DATABASE strapi COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

-- sonarqube
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'sonarqube')
    CREATE DATABASE sonarqube COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

-- treepruning (backend)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'treepruning')
    CREATE DATABASE treepruning COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

PRINT 'Bases de datos creadas: keycloak, strapi, sonarqube, treepruning';
GO
