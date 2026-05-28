#!/bin/bash
# scripts/register-debezium-connectors.sh
#
# Registra los conectores Debezium (sources PostgreSQL + sinks MySQL).
# Incluye una fase de auditoría que detecta conectores existentes que
# podrían colisionar (mismo topic.prefix) y los elimina antes de registrar
# los nuevos, evitando doble publicación en los mismos topics de Redpanda.
#
# Uso:
#   chmod +x scripts/register-debezium-connectors.sh
#   ./scripts/register-debezium-connectors.sh
#
# Opciones de entorno:
#   DEBEZIUM_URL   URL base de Kafka Connect (default: http://localhost:8083)
#   DRY_RUN=1      Muestra lo que haría sin ejecutar cambios

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}══════ $* ══════${NC}"; }

DRY_RUN="${DRY_RUN:-0}"
[[ "$DRY_RUN" == "1" ]] && warn "Modo DRY_RUN activo — no se ejecutarán cambios reales."

# ── Cargar variables ──────────────────────────────────────────────────────────
# Si las variables ya están en el entorno (inyectadas por Infisical o exportadas
# manualmente), se usan directamente sin necesitar el .env.
REQUIRED_VARS=(POSTGRES_USER POSTGRES_PASSWORD MYSQL_USER MYSQL_PASSWORD)
MISSING_VARS=()
for v in "${REQUIRED_VARS[@]}"; do
  [[ -z "${!v:-}" ]] && MISSING_VARS+=("$v")
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  # Intentar cargar desde .env como fallback
  ENV_FILE="$(dirname "$0")/../.env"
  if [[ -f "$ENV_FILE" ]]; then
    info "Cargando variables desde $ENV_FILE"
    set -a; source "$ENV_FILE"; set +a
  else
    error "Faltan variables requeridas: ${MISSING_VARS[*]}"
    error "Opciones:"
    error "  1. Correr con Infisical: infisical run --env=prod -- ./scripts/register-debezium-connectors.sh"
    error "  2. Exportar manualmente: export POSTGRES_USER=... POSTGRES_PASSWORD=... MYSQL_USER=... MYSQL_PASSWORD=..."
    exit 1
  fi
else
  info "Variables de entorno detectadas (${#REQUIRED_VARS[@]} requeridas presentes)."
fi

CONNECT_URL="${DEBEZIUM_URL:-http://localhost:8083}"
CONNECTORS_DIR="$(dirname "$0")/../docker/debezium/connectors"

# ── Esperar a que Kafka Connect esté listo ────────────────────────────────────
step "Verificando disponibilidad de Debezium Connect"
for i in $(seq 1 30); do
  if curl -sf "$CONNECT_URL/connectors" -o /dev/null 2>&1; then
    info "Debezium Connect disponible en $CONNECT_URL"; break
  fi
  [[ $i -eq 30 ]] && { error "Debezium no respondió. ¿Está el stack corriendo?"; exit 1; }
  echo "  Intento $i/30 — esperando 5s..."; sleep 5
done

# ── Auditoría: mostrar conectores actuales ────────────────────────────────────
step "Conectores actualmente registrados en Debezium"
EXISTING_CONNECTORS=$(curl -sf "$CONNECT_URL/connectors" | tr -d '[]"' | tr ',' '\n' | tr -d ' ')

if [[ -z "$EXISTING_CONNECTORS" ]]; then
  info "No hay conectores registrados. Instalación limpia."
else
  warn "Conectores existentes detectados:"
  for c in $EXISTING_CONNECTORS; do
    STATUS=$(curl -sf "$CONNECT_URL/connectors/$c/status" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['connector']['state'])" 2>/dev/null || echo "DESCONOCIDO")
    echo "  • $c  [$STATUS]"
  done
fi

# ── Detectar y eliminar conectores que colisionarían ─────────────────────────
# Un conector source colisiona si usa el mismo topic.prefix que uno de los nuevos
# (treepruning, keycloak, strapi). Si coexiste con el nuevo source, ambos
# publicarían en los mismos topics → doble CDC, doble invalidación de caché,
# posible corrupción del offset del sink.
step "Limpieza de conectores conflictivos"

# Prefijos/nombres de los nuevos conectores que vamos a registrar
NEW_CONNECTOR_NAMES=("pg-source-treepruning" "pg-source-keycloak" "pg-source-strapi"
                     "mysql-sink-treepruning" "mysql-sink-keycloak" "mysql-sink-strapi")
TOPIC_PREFIXES=("treepruning" "keycloak" "strapi")

for c in $EXISTING_CONNECTORS; do
  # Saltar si el nombre coincide exactamente con uno de los nuevos (lo manejamos luego)
  is_new=0
  for new_name in "${NEW_CONNECTOR_NAMES[@]}"; do
    [[ "$c" == "$new_name" ]] && { is_new=1; break; }
  done
  [[ $is_new -eq 1 ]] && continue

  # Obtener la configuración del conector para ver su topic.prefix o database.server.name
  CONFIG=$(curl -sf "$CONNECT_URL/connectors/$c/config" 2>/dev/null || echo "{}")
  CONNECTOR_PREFIX=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('topic.prefix') or d.get('database.server.name',''))
" 2>/dev/null || echo "")

  CONFLICTS=0
  for prefix in "${TOPIC_PREFIXES[@]}"; do
    [[ "$CONNECTOR_PREFIX" == "$prefix" ]] && { CONFLICTS=1; break; }
  done

  if [[ $CONFLICTS -eq 1 ]]; then
    warn "Conector '$c' usa topic.prefix='$CONNECTOR_PREFIX' — colisiona con los nuevos."
    if [[ "$DRY_RUN" == "1" ]]; then
      warn "[DRY_RUN] Se eliminaría: $c"
    else
      read -rp "  ¿Eliminar '$c' antes de registrar el nuevo? [s/N]: " CONFIRM
      if [[ "${CONFIRM,,}" == "s" ]]; then
        curl -sf -X DELETE "$CONNECT_URL/connectors/$c"
        info "  ✓ '$c' eliminado."
        # Recordatorio de replication slot huérfano
        warn "  ATENCIÓN: El slot de replicación que usaba '$c' en pg1 puede haber quedado"
        warn "  huérfano. Verifícalo y elimínalo si es necesario:"
        warn "    docker exec pg1 psql -U \$POSTGRES_USER -c \"SELECT slot_name FROM pg_replication_slots;\""
        warn "    docker exec pg1 psql -U \$POSTGRES_USER -c \"SELECT pg_drop_replication_slot('<slot_name>');\""
      else
        warn "  '$c' conservado. Puede causar doble publicación en topics '$CONNECTOR_PREFIX.*'."
      fi
    fi
  fi
done

# ── Función de registro ───────────────────────────────────────────────────────
register_connector() {
  local file="$1"
  local name
  name=$(python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" < "$file" 2>/dev/null \
         || grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | cut -d'"' -f4)

  if curl -sf "$CONNECT_URL/connectors/$name" -o /dev/null 2>&1; then
    warn "Conector '$name' ya existe — omitiendo."
    warn "  Para forzar re-registro: curl -X DELETE $CONNECT_URL/connectors/$name"
    return
  fi

  [[ "$DRY_RUN" == "1" ]] && { info "[DRY_RUN] Registraría: $name"; return; }

  info "Registrando: $name"
  local payload
  payload=$(sed \
    -e "s|\${file:/kafka/config/connector.properties:POSTGRES_USER}|${POSTGRES_USER}|g" \
    -e "s|\${file:/kafka/config/connector.properties:POSTGRES_PASSWORD}|${POSTGRES_PASSWORD}|g" \
    -e "s|\${file:/kafka/config/connector.properties:MYSQL_USER}|${MYSQL_USER}|g" \
    -e "s|\${file:/kafka/config/connector.properties:MYSQL_PASSWORD}|${MYSQL_PASSWORD}|g" \
    "$file")

  local http_code
  http_code=$(echo "$payload" | curl -s -o /tmp/debezium_response.json -w "%{http_code}" \
    -X POST "$CONNECT_URL/connectors" -H "Content-Type: application/json" -d @-)

  if [[ "$http_code" =~ ^2 ]]; then
    info "  ✓ '$name' registrado (HTTP $http_code)"
  else
    error "  Error al registrar '$name' (HTTP $http_code):"
    cat /tmp/debezium_response.json; exit 1
  fi
}

# ── Registrar sources primero, luego sinks ────────────────────────────────────
step "Registrando SOURCE connectors (PostgreSQL → Redpanda)"
info "Nota: snapshot.mode=initial — Debezium copiará todos los datos actuales de"
info "pg1 antes de activar el CDC continuo. Esto puede tardar según el volumen."
register_connector "$CONNECTORS_DIR/source-treepruning.json"
register_connector "$CONNECTORS_DIR/source-keycloak.json"
register_connector "$CONNECTORS_DIR/source-strapi.json"

step "Registrando SINK connectors (Redpanda → MySQL)"
register_connector "$CONNECTORS_DIR/sink-mysql-treepruning.json"
register_connector "$CONNECTORS_DIR/sink-mysql-keycloak.json"
register_connector "$CONNECTORS_DIR/sink-mysql-strapi.json"

# ── Estado final ──────────────────────────────────────────────────────────────
step "Estado final de conectores"
curl -sf "$CONNECT_URL/connectors?expand=status" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, info in data.items():
    state = info.get('status', {}).get('connector', {}).get('state', '?')
    tasks = info.get('status', {}).get('tasks', [])
    task_states = ', '.join(t.get('state','?') for t in tasks) or 'sin tasks'
    print(f'  {name}: {state} | tasks: {task_states}')
" 2>/dev/null || curl -sf "$CONNECT_URL/connectors"

echo ""
info "Comandos útiles de monitoreo:"
info "  Ver estado de un conector:  curl $CONNECT_URL/connectors/pg-source-treepruning/status | python3 -m json.tool"
info "  Ver slots en pg1:           docker exec pg1 psql -U \$POSTGRES_USER -c 'SELECT slot_name, active, restart_lsn FROM pg_replication_slots;'"
info "  Ver lag de replicación:     docker exec pg1 psql -U \$POSTGRES_USER -c 'SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag FROM pg_replication_slots;'"
