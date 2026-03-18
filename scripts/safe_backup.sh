#!/usr/bin/env bash
set -euo pipefail

# Safe PostgreSQL backup for Odoo docker-compose setup.
# - Verifies DB exists before dumping
# - Shows quick sanity metrics (products + installed modules)
# - Uses binary-safe dump command (NO -t)
# - Verifies dump archive readability after creation

usage() {
  cat <<'EOF'
Usage:
  bash scripts/safe_backup.sh <db_name> [output_prefix]

Examples:
  bash scripts/safe_backup.sh coffee_shop_empty
  bash scripts/safe_backup.sh coffee_shop backup_empty
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DB_NAME="${1:-}"
PREFIX="${2:-${DB_NAME:-backup}}"
DB_CONTAINER="${DB_CONTAINER:-odoo-db}"
BACKUP_DIR="${BACKUP_DIR:-backups}"

ensure_db_container_running() {
  if docker ps --format '{{.Names}}' | awk -v n="${DB_CONTAINER}" '$0==n{found=1} END{exit !found}'; then
    return 0
  fi
  echo "Container '${DB_CONTAINER}' is not running. Trying: docker compose up -d db"
  docker compose up -d db >/dev/null
  if docker ps --format '{{.Names}}' | awk -v n="${DB_CONTAINER}" '$0==n{found=1} END{exit !found}'; then
    return 0
  fi
  echo "ERROR: container '${DB_CONTAINER}' is not running after compose up."
  echo "Hint: check 'docker compose ps' and Docker Desktop status."
  exit 1
}

if [[ -z "${DB_NAME}" ]]; then
  echo "ERROR: missing <db_name>."
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command not found."
  exit 1
fi

ensure_db_container_running

DB_EXISTS="$(docker exec "${DB_CONTAINER}" psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}' LIMIT 1;")"
if [[ "${DB_EXISTS}" != "1" ]]; then
  echo "ERROR: database '${DB_NAME}' does not exist."
  exit 1
fi

PRODUCT_COUNT="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${DB_NAME}" -tAc "SELECT COALESCE((SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='product_template'),0);")"
if [[ "${PRODUCT_COUNT}" == "1" ]]; then
  PRODUCT_COUNT="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${DB_NAME}" -tAc "SELECT count(*) FROM product_template;")"
else
  PRODUCT_COUNT="n/a (table product_template not found)"
fi

INSTALLED_MODULES="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${DB_NAME}" -tAc "SELECT COALESCE((SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='ir_module_module'),0);")"
if [[ "${INSTALLED_MODULES}" == "1" ]]; then
  INSTALLED_MODULES="$(docker exec "${DB_CONTAINER}" psql -U odoo -d "${DB_NAME}" -tAc "SELECT count(*) FROM ir_module_module WHERE state='installed';")"
else
  INSTALLED_MODULES="n/a (table ir_module_module not found)"
fi

mkdir -p "${BACKUP_DIR}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="${BACKUP_DIR}/${PREFIX}_${TS}.dump"
META_FILE="${BACKUP_DIR}/${PREFIX}_${TS}.meta.txt"

echo "Database            : ${DB_NAME}"
echo "Installed modules   : ${INSTALLED_MODULES}"
echo "Product count       : ${PRODUCT_COUNT}"
echo "Output              : ${OUT_FILE}"
echo ""
echo "Creating dump..."

# IMPORTANT: no -t flag here, to avoid corrupting custom-format dump stream.
docker exec "${DB_CONTAINER}" pg_dump -U odoo -d "${DB_NAME}" -Fc > "${OUT_FILE}"

echo "Verifying dump archive..."
docker exec -i "${DB_CONTAINER}" pg_restore -l < "${OUT_FILE}" >/dev/null

SIZE="$(ls -lh "${OUT_FILE}" | awk '{print $5}')"
SHA256="$(shasum -a 256 "${OUT_FILE}" | awk '{print $1}')"

cat > "${META_FILE}" <<EOF
db_name=${DB_NAME}
created_at=${TS}
dump_file=${OUT_FILE}
size=${SIZE}
sha256=${SHA256}
installed_modules=${INSTALLED_MODULES}
product_count=${PRODUCT_COUNT}
EOF

echo "Done."
echo "Dump file : ${OUT_FILE}"
echo "Meta file : ${META_FILE}"
echo "SHA256    : ${SHA256}"
