#  Tree Pruning -- Infraestructura

Sistema de Gestión de Arbolado Urbano -- Rionegro, Antioquia  
**Azure VM** - **Docker Compose** - **Traefik** - **Infisical** - **GitHub Actions**

---

## Arquitectura

```
Internet
  +-- Cloudflare (WAF + CDN + DNS)
        +-- Azure VM: vm-treepruning (Standard_B4ms, Ubuntu 22.04)
              Dominio: treepruning.org
              |
              +-- Traefik v2.11 (SSL Let's Encrypt vía Cloudflare DNS)
                    +-- treepruning.org         -> tp-frontend       (prod)
                    +-- dev.treepruning.org     -> tp-frontend-dev   (dev)
                    +-- api.treepruning.org     -> tp-kong :8000     (prod, vía Kong)
                    +-- api-dev.treepruning.org -> tp-backend-dev :8080 (dev, directo)
                    +-- auth.treepruning.org    -> tp-keycloak :8080
                    +-- cms.treepruning.org     -> tp-strapi :1337
                    +-- s3.treepruning.org      -> tp-minio :9000
                    +-- console.treepruning.org -> tp-minio :9001
                    +-- grafana.treepruning.org -> tp-grafana :3000
                    +-- sonar.treepruning.org   -> tp-sonarqube :9000

Servicios externos (SaaS -- sin contenedor):
  +-- Infisical          -- gestión de secretos (reemplaza HashiCorp Vault)
  +-- Firebase Cloud Messaging -- notificaciones push
  +-- Google Maps Platform     -- mapas interactivos
  +-- GitHub Actions           -- CI/CD pipeline
  +-- Google reCAPTCHA v3      -- validación anti-bot
```

## Estructura del repositorio

```
treepruning-infra/
+-- docker-compose.yml                    # Todos los servicios + labels Traefik
+-- infisical.json.example                # Plantilla -- el real se genera en bootstrap
+-- .gitignore                            # Bloquea .env, .pem, *.key, acme.json
+-- .github/
|   +-- workflows/
|       +-- bootstrap.yml                 #  Setup inicial (1 vez por VM nueva) 
|       +-- deploy.yml                    #  Deploy completo (push a main / manual)
|       +-- update-service.yml            #  Update incremental (dispatch desde back/front)
+-- docker/
|   +-- postgres/
|   |   +-- init-multiple-dbs.sh         # Crea: kong, keycloak, strapi, sonarqube
|   +-- prometheus/
|   |   +-- prometheus.yml
|   +-- nginx/
|   |   +-- frontend.conf                # Config nginx (legacy, preservado)
|   +-- traefik/
|   |   +-- traefik.yml                  # Config estática (dashboard + ACME)
|   |   +-- dynamic/
|   |   |   +-- middlewares.yml          # IP whitelist + security headers (opcional)
|   |   +-- letsencrypt/                 # Certificados -- generados en runtime (ignored)
|   +-- config-repo/
|       +-- treepruning.yml              # Parámetros de Spring Cloud Config
+-- scripts/
    +-- bootstrap.sh                      # Setup completo desde cero (lo llama bootstrap.yml)
    +-- setup-strapi.sh                   # Genera strapi-app/ (solo 1ra vez)
    +-- fix-kong.sh                       # Fix pg_hba.conf para Kong (solo 1ra vez)
    +-- ci-renew-token.sh                 # Renueva token Infisical desde CI
    +-- renew-token.sh                    # Renueva token Infisical manualmente
```

>  El archivo `infisical.json` NO se versiona -- contiene el `workspaceId` (Project ID).  
> El pipeline lo genera automáticamente desde el secret `INFISICAL_PROJECT_ID`.

---

##  Secretos -- dónde vive cada uno

Este proyecto usa **dos fuentes de secretos** con responsabilidades distintas:

### 1 GitHub Actions -- Repository Secrets
> **Settings -> Secrets and variables -> Actions -> Repository secrets**

Hay dos conjuntos de secrets, según qué workflow los usa:

####  Siempre requeridos (workflows: `deploy.yml`, `update-service.yml`)
| Secret | Valor |
|--------|-------|
| `AZURE_HOST` | IP pública de la VM |
| `AZURE_USER` | `treepruning` |
| `AZURE_SSH_KEY` | Contenido del archivo `.pem` de la VM |

####  Solo para bootstrap (workflow: `bootstrap.yml`, una sola vez por VM nueva)
| Secret | Cómo obtenerlo |
|--------|----------------|
| `INFISICAL_CLIENT_ID` | Machine Identity en Infisical -> Universal Auth |
| `INFISICAL_CLIENT_SECRET` | Machine Identity en Infisical -> Universal Auth |
| `INFISICAL_PROJECT_ID` | Infisical -> Project Settings -> Project ID |

>  **Los secrets de Infisical solo se usan en `bootstrap.yml`**. Una vez ejecutado, viven en `~/.bashrc` de la VM y los workflows de deploy regulares no los necesitan en GitHub. Si decides borrarlos de GitHub después del bootstrap, los deploys regulares siguen funcionando.

---

### 2 Infisical -- Environments `dev` y `prod`
> **app.infisical.com -> treepruning -> {dev | prod}**  
> Son los secretos que se inyectan a Docker Compose en tiempo de ejecución. Ninguno vive en el repo ni en GitHub.

El proyecto usa **dos environments en paralelo** sobre la misma VM:
- `dev` aplica a los servicios `backend-dev` y `frontend-dev`.
- `prod` aplica a los servicios `backend`, `frontend` y a todos los servicios compartidos (pg1, redis, keycloak, kong, minio, strapi, etc.).

La mayoría de los secretos son **iguales en ambos environments** (passwords, tokens, credenciales compartidas). Solo las variables que aíslan datos/entornos difieren:

| Variable | Valor en `dev` | Valor en `prod` |
|---|---|---|
| `POSTGRES_DB` | `treepruning_dev` | `treepruning_prod` |
| `STORAGE_MINIO_BUCKET` | `evidencias-dev` | `evidencias-prod` |
| `APP_ENVIRONMENT` | `dev` | `prod` |

#### Secretos comunes (idénticos en `dev` y `prod`)

| Secret en Infisical | Para qué |
|---------------------|----------|
| `ACME_EMAIL` | Email para notificaciones de Let's Encrypt |
| `AZURE_HOST` | IP de la VM (referencia interna) |
| `AZURE_SSH_KEY` | Clave SSH (referencia interna) |
| `AZURE_USER` | Usuario SSH (referencia interna) |
| `CF_DNS_API_TOKEN` | Token Cloudflare para SSL automático con Let's Encrypt |
| `GHCR_OWNER` | Propietario de los packages en GHCR |
| `GHCR_TOKEN` | PAT de GitHub para `docker login ghcr.io` en la VM |
| `GHCR_USER` | Usuario asociado al `GHCR_TOKEN` |
| `GOOGLE_CAPTCHA_V3` | Clave de Google reCAPTCHA v3 |
| `GRAFANA_PASSWORD` | Contraseña admin de Grafana |
| `KEYCLOAK_ADMIN_PASSWORD` | Contraseña admin de Keycloak |
| `KEYCLOAK_ADMIN_USER` | Usuario admin de Keycloak |
| `MINIO_ROOT_PASSWORD` | Contraseña root de MinIO |
| `MINIO_ROOT_USER` | Usuario root de MinIO |
| `POSTGRES_PASSWORD` | Contraseña de PostgreSQL |
| `POSTGRES_USER` | `postgres` |
| `PUBLIC_URL` | URL pública del CMS (Strapi) |
| `REDIS_PASSWORD` | Contraseña de Redis |
| `SONARQUBE_ADMIN_PASSWORD` | Contraseña admin de SonarQube |
| `STRAPI_ADMIN_JWT_SECRET` | Secret JWT del panel admin de Strapi |
| `STRAPI_APP_KEYS` | `key1,key2,key3,key4` |
| `STRAPI_JWT_SECRET` | Secret JWT de la API de Strapi |
| `VAULT_TOKEN` | Token de acceso a Infisical (renovación automática) |
| `VITE_GOOGLE_MAPS_API_KEY` | API Key de Google Maps para el Frontend |

> Pasar de un environment a otro: el workflow `deploy.yml` levanta cada grupo de servicios con `infisical run --env=...`. Los servicios `*-dev` se levantan con `--env=dev`, todo lo demás con `--env=prod`. Ver sección _Separación prod/dev_ más abajo.

---

##  Deploy desde cero -- VM nueva

> 100% automatizado desde GitHub Actions. **No requiere conectarse a la VM por SSH manualmente**.

### Paso 1 -- DNS en Cloudflare

Crear registros tipo **A** apuntando a la IP de la VM con proxy activado ():

| Subdominio | Servicio |
|------------|---------|
| `@` (raíz) | Frontend (prod) |
| `www` | Frontend (prod, alias) |
| `dev` | Frontend (dev) |
| `api` | Kong (API Gateway) |
| `api-dev` | Backend (dev directo, sin Kong) |
| `auth` | Keycloak |
| `cms` | Strapi |
| `s3` | MinIO API |
| `console` | MinIO Consola |
| `grafana` | Grafana |
| `sonar` | SonarQube |
| `traefik` | Traefik Dashboard |

### Paso 2 -- Configurar los 6 GitHub Secrets

En el repositorio -> **Settings -> Secrets and variables -> Actions -> New repository secret**:

- `AZURE_HOST`, `AZURE_USER`, `AZURE_SSH_KEY` (siempre necesarios)
- `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`, `INFISICAL_PROJECT_ID` (solo para bootstrap)

### Paso 3 -- Ejecutar el workflow ` Bootstrap servidor`

**Actions ->  Bootstrap servidor (1 vez por VM nueva) -> Run workflow**.  
En el campo `confirm` escribir exactamente: **`BOOTSTRAP`**.

El workflow:
1. Sincroniza el repo a la VM.
2. Instala Docker e Infisical CLI.
3. Configura el kernel (`vm.max_map_count` para SonarQube).
4. Hace login con la Machine Identity de Infisical y planta el token + credenciales en `~/.bashrc`.
5. Crea el proyecto Strapi si no existe.

A partir de aquí, **los workflows de deploy ya no necesitan los secrets de Infisical en GitHub** -- los leen del bashrc del servidor.

### Paso 4 -- Primer deploy

**Actions ->  Deploy Tree Pruning -> Run workflow -> action: `deploy`**.

El pipeline sincroniza archivos, renueva el token de Infisical (si las credenciales están en bashrc), levanta los contenedores con `docker compose up -d` inyectando los secretos desde Infisical, y muestra el estado.

### Paso 5 -- Fix de Kong (solo la primera vez)

**Actions ->  Deploy Tree Pruning -> Run workflow -> action: `fix-kong`**.

> Kong tiene un problema histórico con `scram-sha-256` en pg_hba. El fix lo cambia a `md5` solo para Kong.

### Paso 6 -- (Opcional) Limpiar secrets de Infisical en GitHub

Una vez completado el bootstrap, puedes borrar `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` e `INFISICAL_PROJECT_ID` de GitHub Secrets -- los deploys regulares no los necesitan.

> Recomendado mantenerlos si planeas levantar otro servidor en el futuro o re-provisionar este. Sin ellos no puedes correr `bootstrap.yml` de nuevo.

---

##  Deploy en adelante

Cada `push` a `main` dispara el deploy automáticamente.  
Para operaciones puntuales, usar **Actions -> Run workflow**:

| Acción | Cuándo usarla |
|--------|---------------|
| `deploy` | Levantar / actualizar servicios (default en push) |
| `restart` | Reiniciar todos los contenedores |
| `down` | Apagar el stack |
| `fix-kong` | Fix de pg_hba -- **solo una vez** en servidor nuevo |
| `renew-token` | Forzar renovación del token de Infisical |

> El token de Infisical se renueva automáticamente en cada deploy -- no es necesario renovarlo a mano.

---

##  Comandos en la VM (día a día)

```bash
# Aliases disponibles después del bootstrap
tp-up              # Levantar todos los servicios con Infisical
tp-down            # Apagar el stack
tp-ps              # Estado de contenedores
tp-logs            # Logs en tiempo real
tp-renew-token     # Renovar token de Infisical manualmente

# Logs por servicio
docker logs tp-traefik   --tail=50
docker logs tp-kong      --tail=50
docker logs tp-keycloak  --tail=50
docker logs tp-strapi    --tail=50
docker logs tp-grafana   --tail=50
docker logs tp-sonarqube --tail=50

# Recursos
docker stats --no-stream
```

---

##  URLs de acceso

| Servicio | URL | Environment | Credenciales (en Infisical) |
|----------|-----|---|-----------------------------|
| Frontend | `https://treepruning.org` | prod | -- |
| Frontend Dev | `https://dev.treepruning.org` | dev | -- |
| API Gateway (vía Kong) | `https://api.treepruning.org` | prod | -- |
| Backend Dev (directo) | `https://api-dev.treepruning.org` | dev | -- |
| Keycloak Admin | `https://auth.treepruning.org/admin` | shared | `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD` |
| Strapi Admin | `https://cms.treepruning.org/admin` | shared | Crear en primer acceso |
| MinIO Consola | `https://console.treepruning.org` | shared | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| MinIO API S3 | `https://s3.treepruning.org` | shared | -- |
| Grafana | `https://grafana.treepruning.org` | shared | `admin` / `GRAFANA_PASSWORD` |
| SonarQube | `https://sonar.treepruning.org` | shared | `admin` / `SONARQUBE_ADMIN_PASSWORD` |

---

##  Separación prod/dev

Tanto `prod` como `dev` corren en la **misma VM** y comparten infraestructura (pg1, redis, keycloak, kong, minio, strapi, etc.). El aislamiento se logra por:

| Eje | prod | dev | Compartido |
|---|---|---|---|
| Container backend | `tp-backend` | `tp-backend-dev` | -- |
| Container frontend | `tp-frontend` | `tp-frontend-dev` | -- |
| Imagen Docker | `:latest` | `:dev` | -- |
| Branch que dispara el build | `main` (en repos back/front) | `develop` (en repos back/front) | -- |
| DB en pg1 | `treepruning_prod` | `treepruning_dev` | `keycloak`, `kong`, `strapi`, `sonarqube` |
| Bucket MinIO | `evidencias-prod` | `evidencias-dev` | -- |
| Env Infisical inyectado | `prod` | `dev` | -- |
| Subdominio | `treepruning.org`, `api.treepruning.org` | `dev.treepruning.org`, `api-dev.treepruning.org` | resto (`auth`, `cms`, etc.) |

#### Workflows

| Workflow | Comportamiento |
|---|---|
| `deploy.yml` | Levanta `$PROD_SERVICES` con `--env=prod` y `$DEV_SERVICES` (`backend-dev`, `frontend-dev`) con `--env=dev` en dos pasadas. |
| `update-service.yml` | Recibe `service` por dispatch. Si termina en `-dev` → `--env=dev`; si no → `--env=prod`. |

> **No hay branch `develop` en `treepruning-infra`**. El infra se trabaja siempre sobre `main` (con feature branches puntuales vía PR para cambios riesgosos). La separación prod/dev en infra ocurre por env de Infisical, no por branch. Los repos `treepruning-backend` y `treepruning-frontend` sí pueden usar `develop` para disparar builds que produzcan imágenes `:dev`.

---

##  Acceso a servicios internos (túnel SSH)

PostgreSQL desde DBeaver / pgAdmin en tu PC:

```powershell
# Windows -- PowerShell (dejar la ventana abierta)
ssh -i "vm-treepruning_key.pem" -L 5432:localhost:5432 treepruning@TU_IP_VM -N
# Conectar a: localhost:5432
```

Kong Admin API:

```powershell
ssh -i "vm-treepruning_key.pem" -L 8001:localhost:8001 treepruning@TU_IP_VM -N
# Abrir: http://localhost:8001
```

---

##  Configuración post-instalación (solo 1ra vez)

### MinIO
1. `https://console.treepruning.org` -> login con `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
2. **Buckets -> Create Bucket** -> nombres: `evidencias-prod` y `evidencias-dev` (uno por environment)
3. Ambos buckets son **privados** -- el backend genera URLs prefirmadas on-demand (15 min) para servir las fotos

### Grafana
1. `https://grafana.treepruning.org` -> login: `admin` / `GRAFANA_PASSWORD`
2. **Connections -> Data Sources -> Add -> Prometheus** -> URL: `http://tp-prometheus:9090` -> Save & Test
3. Importar dashboard ID `12900`

### Strapi
1. `https://cms.treepruning.org/admin` -> crear cuenta de administrador
2. **Content-Type Builder** -> crear colecciones:
   - `NotificationTemplate`: `title`, `body`, `type` (enum: VENCIMIENTO_PQR, BLOQUEO_CUENTA, PODA_ASIGNADA, ALERTA_SISTEMA), `active` (boolean)
   - `SystemMessage`: `key` (único), `value`, `module` (INVENTARIO, PODAS, PQR, REPORTES, COMUN)
3. **Settings -> API Tokens -> Create Token** -> Full Access -> copiar para el Backend

### Keycloak
1. `https://auth.treepruning.org/admin` -> login con `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD`
2. **Create Realm** -> nombre: `treepruning`
3. **Realm roles -> Create role**  3: `ADMINISTRADOR`, `ENCARGADO_CUADRILLA`, `CIUDADANO`
4. **Clients -> Create client** -> `treepruning-backend` (bearer-only)
5. **Clients -> Create client** -> `treepruning-frontend` (Redirect URI: `https://treepruning.org/*`)
6. **Users -> Create user** -> asignar rol `ADMINISTRADOR` -> Credentials -> Set password

### SonarQube
1. `https://sonar.treepruning.org` -> login: `admin` / `admin` -> cambiar contraseña a `SONARQUBE_ADMIN_PASSWORD`

---

##  Notas importantes

- **Aislamiento prod/dev**: pasa por env de Infisical + container separado + tag de imagen, **no por branch**. El compose y los workflows son únicos.
- **Bucket privados**: `evidencias-prod` y `evidencias-dev` no son públicos; el backend emite presigned URLs (15 min) con `GET /api/v1/prunings/{id}/photo-url`.
- **Contraseñas con `#`**: con Infisical CLI sí se permiten (se inyectan como env vars, no por `.env`). La advertencia histórica solo aplica si alguien escribiera un `.env` plano.
- El token de Infisical **se renueva automáticamente** en cada deploy vía CI/CD.
- El fix de Kong (`fix-kong.sh`) **solo se aplica una vez** por servidor nuevo.
- `strapi-app/` se genera en el servidor y **no se versiona** completamente en Git.
- `infisical.json` **no se versiona** -- se genera dinámicamente desde `INFISICAL_PROJECT_ID`.
- Los volúmenes Docker **persisten** entre `down`/`up` -- los datos no se pierden al apagar.
- `AZURE_HOST`, `AZURE_SSH_KEY` y `AZURE_USER` están duplicados en Infisical como referencia, pero el pipeline los toma de GitHub Secrets para conectarse al servidor.
- **`tp-config-server`**: usa la imagen `hyness/spring-cloud-config-server:5.0.0` (Spring Boot 3, JDK 17.0.17). La imagen 3.1.1-jre17 anterior tenia un bug del JDK con cgroup v2 (`NullPointerException` en `CgroupInfo.getMountPoint()` al inicializar el `MBeanServer`); v5.0.0 lo resuelve. `mem_limit` debe ser >= 768MB porque el buildpack de Paketo lo requiere.
