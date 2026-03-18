#!/usr/bin/env bash
set -euo pipefail

# Safe restore for Odoo docker-compose setup.
# - Validates dump archive readability
# - Recreates target DB (drop/create)
# - Restores dump
# - Verifies core Odoo tables
# - Auto-initializes base when dump does not contain full Odoo schema

usage() {
  cat <<'EOF'
Usage:
  bash scripts/safe_restore.sh <target_db_name> <dump_file> [--yes]

Examples:
  bash scripts/safe_restore.sh coffee_shop_new backups/coffee_shop_20260318_112807_ok.dump --yes
  bash scripts/safe_restore.sh coffee_shop_empty backups/backup_empty_20260318_120000.dump --yes

Notes:
  --yes is required (destructive: drops and recreates target DB).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TARGET_DB="${1:-}"
DUMP_FILE="${2:-}"
CONFIRM="${3:-}"
DB_CONTAINER="${DB_CONTAINER:-odoo-db}"
ODOO_CONTAINER="${ODOO_CONTAINER:-odoo-coffee}"

ensure_container_running() {
  local name="$1"
  local service_hint="$2"
  if docker ps --format '{{.Names}}' | awk -v n="${name}" '$0==n{found=1} END{exit !found}'; then
    return 0
  fi
  echo "Container '${name}' is not running. Trying: docker compose up -d ${service_hint}"
  docker compose up -d ${service_hint} >/dev/null
  if docker ps --format '{{.Names}}' | awk -v n="${name}" '$0==n{found=1} END{exit !found}'; then
    return 0
  fi
  echo "ERROR: container '${name}' is not running after compose up."
  echo "Hint: check 'docker compose ps' and Docker Desktop status."
  exit 1
}

if [[ -z "${TARGET_DB}" || -z "${DUMP_FILE}" ]]; then
  echo "ERROR: missing required arguments."
  usage
  exit 1
fi

if [[ "${CONFIRM}" != "--yes" ]]; then
  echo "ERROR: missing --yes confirmation (operation is destructive)."
  usage
  exit 1
fi

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "ERROR: dump file not found: ${DUMP_FILE}"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command not found."
  exit 1
fi

ensure_container_running "${DB_CONTAINER}" "db"
ensure_container_running "${ODOO_CONTAINER}" "odoo"

echo "Validating dump archive..."
docker exec -i "${DB_CONTAINER}" pg_restore -l < "${DUMP_FILE}" >/dev/null

echo "Recreating database: ${TARGET_DB}"
docker exec "${DB_CONTAINER}" dropdb -U odoo --if-exists "${TARGET_DB}"
docker exec "${DB_CONTAINER}" createdb -U odoo "${TARGET_DB}"

echo "Restoring dump into ${TARGET_DB}..."
docker exec -i "${DB_CONTAINER}" pg_restore -U odoo -d "${TARGET_DB}" < "${DUMP_FILE}"

IR_MODULE_TABLE="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${TARGET_DB}" -tAc "SELECT to_regclass('public.ir_module_module');" | tr -d '[:space:]')"
IR_HTTP_TABLE="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${TARGET_DB}" -tAc "SELECT to_regclass('public.ir_http');" | tr -d '[:space:]')"

if [[ -z "${IR_MODULE_TABLE}" || -z "${IR_HTTP_TABLE}" ]]; then
  echo "Detected partial/empty dump (core Odoo tables missing)."
  echo "Initializing base module without demo data..."
  docker exec "${ODOO_CONTAINER}" bash -lc "odoo -d ${TARGET_DB} -i base --without-demo=all --stop-after-init --db_host db --db_port 5432 --db_user odoo --db_password odoo_password"
fi

INSTALLED_MODULES="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${TARGET_DB}" -tAc "SELECT count(*) FROM ir_module_module WHERE state='installed';" | tr -d '[:space:]')"
PRODUCT_COUNT="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${TARGET_DB}" -tAc "SELECT COALESCE(count(*),0) FROM product_template;" 2>/dev/null | tr -d '[:space:]' || true)"
PRODUCT_COUNT="${PRODUCT_COUNT:-0}"

echo "Restarting Odoo service..."
docker compose restart odoo >/dev/null

echo "Done."
echo "Target DB          : ${TARGET_DB}"
echo "Installed modules  : ${INSTALLED_MODULES}"
echo "Product count      : ${PRODUCT_COUNT}"
