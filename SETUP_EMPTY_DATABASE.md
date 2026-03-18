# Setup Empty Database (Odoo + Docker)

This guide recreates a fresh Odoo database with empty business data.

## 0) Prerequisites

- Run commands from project root.
- Docker Desktop is running.
- Existing services are defined in `docker-compose.yml`.

## 1) Start containers

```bash
docker compose up -d
docker compose ps
```

## 2) Choose database name

Example in this guide:

```text
coffee_shop_empty
```

## 3) Remove old database (optional, destructive)

Only run this if you want to recreate the same database name from scratch.

```bash
docker exec odoo-db dropdb -U odoo --if-exists coffee_shop_empty
```

## 4) Create empty PostgreSQL database

```bash
docker exec odoo-db createdb -U odoo coffee_shop_empty
```

## 5) Initialize Odoo base (no demo data)

This creates all core Odoo tables in a clean state.

```bash
docker exec odoo-coffee bash -lc "odoo -d coffee_shop_empty -i base --without-demo=all --stop-after-init --db_host db --db_port 5432 --db_user odoo --db_password odoo_password"
```

## 6) Point Odoo to new database

Edit `config/odoo.conf`:

```ini
db_name = coffee_shop_empty
```

Then restart Odoo service:

```bash
docker compose restart odoo
```

## 7) Verify

Open:

```text
http://localhost:8069
```

Expected:
- Login page works
- No old records from previous databases
- Database is usable for fresh setup

## 8) Optional: quick sanity checks in PostgreSQL

```bash
docker exec odoo-db psql -U odoo -d coffee_shop_empty -tAc "SELECT to_regclass('public.ir_module_module');"
docker exec odoo-db psql -U odoo -d coffee_shop_empty -tAc "SELECT count(*) FROM ir_module_module WHERE state='installed';"
```

If these queries return valid values, initialization succeeded.

Create empty database
docker exec odoo-db dropdb -U odoo --if-exists coffee_shop_empty
docker exec odoo-db createdb -U odoo coffee_shop_empty
docker exec odoo-coffee bash -lc "odoo -d coffee_shop_empty -i base --without-demo=all --stop-after-init --db_host db --db_port 5432 --db_user odoo --db_password odoo_password"
docker compose restart odoo


List database và current database in Odoo

CURRENT_DB=$(awk -F'=' '/^[[:space:]]*db_name[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2}' config/odoo.conf); \
echo "Current db_name in odoo.conf: $CURRENT_DB"; \
docker exec odoo-db psql -U odoo -d postgres -tAc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" | \
while read -r db; do [ "$db" = "$CURRENT_DB" ] && echo "* $db (current)" || echo "  $db"; done