# Database Backup and Restore (Odoo + Docker)

## 1) Backup current database

Run from project root:

```bash
mkdir -p backups
docker exec odoo-db pg_dump -U odoo -d coffee_shop_new -Fc > backups/coffee_shop_new_$(date +%Y%m%d_%H%M%S).dump
```

Check backup file:

```bash
ls -lh backups
```

## 2) Restore on another machine

### Step A - Start containers

```bash
docker compose up -d
```

### Step B - Create target database

```bash
docker exec -it odoo-db createdb -U odoo coffee_shop_new
```

### Step C - Restore from dump

```bash
docker exec -i odoo-db pg_restore -U odoo -d coffee_shop_new < backups/coffee_shop_new_YYYYMMDD_HHMMSS.dump
```

## 3) Point Odoo to restored database

In `config/odoo.conf`, set:

```ini
db_name = coffee_shop_new
```

Then restart Odoo:

```bash
docker compose restart odoo
```

## 4) Important notes

- Do not use `-t` with `docker exec` when creating binary dump (`-Fc`), because TTY can corrupt the archive and `pg_restore` will fail with `end of file`.
- Backup files are ignored by Git via `.gitignore`:
  - `backups/*.dump`
  - `backups/*.sql`
  - `backups/*.tar`
- Do not push real database dumps to public repositories.

## 5) Optional automation scripts

Use helper scripts in `scripts/`:

```bash
bash scripts/safe_backup.sh coffee_shop
bash scripts/safe_restore.sh coffee_shop_new backups/coffee_shop_YYYYMMDD_HHMMSS.dump --yes
```



