# Odoo Coffee Shop — Tài liệu tổng quan

## Thông tin cơ bản

| | |
|---|---|
| Odoo | 18.0 |
| PostgreSQL | 15 |
| Container | Docker Compose |
| Web | http://localhost:8069 |

**Credentials:**

| | |
|---|---|
| DB User | `odoo` |
| DB Password | `odoo_password` |
| Admin master password | `admin_master_password_123` |
| Odoo app user | `admin` / (mật khẩu đặt khi setup lần đầu) |

---

## Setup

### 1. Khởi động containers

```bash
docker compose up -d
```

Kiểm tra trạng thái:

```bash
docker compose ps
```

### 2. Tắt containers

```bash
docker compose down        # giữ data
docker compose down -v     # XÓA toàn bộ data (nguy hiểm!)
```

---

## Tạo database mới (empty)

```bash
# Chọn tên DB, ví dụ: coffee_shop_v1
docker exec odoo-coffee bash -lc "odoo -d coffee_shop_v1 -i base \
  --without-demo=all --stop-after-init \
  --db_host db --db_port 5432 \
  --db_user odoo --db_password odoo_password"
```

Sau đó trỏ Odoo vào DB mới trong `config/odoo.conf`:

```ini
db_name = coffee_shop_v1
```

Restart Odoo:

```bash
docker compose restart odoo
```

---

## Backup

```bash
bash scripts/safe_backup.sh <db_name> [output_prefix]

# Ví dụ:
bash scripts/safe_backup.sh coffee_shop_v0_20260318_134912
bash scripts/safe_backup.sh coffee_shop_v0_20260318_134912 coffee_shop_v0
```

File dump + metadata được lưu vào `backups/`. Script tự động:
- Kiểm tra DB tồn tại
- Hiển thị số module & sản phẩm
- Tạo SHA256 checksum
- Verify dump sau khi tạo

---

## Restore

```bash
bash scripts/safe_restore.sh <target_db> <dump_file> --yes

# Ví dụ:
bash scripts/safe_restore.sh coffee_shop_v0 \
  backups/coffee_shop_v0_20260318_134912.dump --yes
```

Script tự động:
- Validate dump archive
- Drop + recreate DB
- Restore data
- Verify Odoo core tables
- Restart Odoo service

Sau restore, cập nhật `config/odoo.conf`:

```ini
db_name = coffee_shop_v0
```

---

## Đổi mật khẩu

### Đổi admin master password (odoo.conf)

Sửa `config/odoo.conf`:

```ini
admin_passwd = new_master_password
```

Restart: `docker compose restart odoo`

### Đổi DB password (odoo_password)

Cập nhật đồng thời 3 chỗ:

1. `docker-compose.yml` — `POSTGRES_PASSWORD` và `PASSWORD`
2. `config/odoo.conf` — `db_password`

Sau đó:

```bash
docker compose down
docker compose up -d
```

> **Lưu ý:** Volume PostgreSQL lưu password hash từ lần khởi tạo đầu tiên. Nếu đã có data, phải đổi password bên trong DB trước:
> ```bash
> docker exec -it odoo-db psql -U odoo -c "ALTER USER odoo PASSWORD 'new_password';"
> ```

---

## Tương tác database (psql)

### Mở psql shell

```bash
docker exec -it odoo-db psql -U odoo -d <db_name>

# Ví dụ:
docker exec -it odoo-db psql -U odoo -d coffee_shop_v0_20260318_134912
```

### Các lệnh psql thường dùng

```sql
-- Liệt kê databases
\l

-- Liệt kê tables
\dt

-- Chuyển database
\c other_db_name

-- Thoát
\q
```

### Query trực tiếp (không vào shell)

```bash
# Đếm sản phẩm
docker exec odoo-db psql -U odoo -d <db_name> -tAc \
  "SELECT count(*) FROM product_template;"

# Xem modules đã cài
docker exec odoo-db psql -U odoo -d <db_name> -tAc \
  "SELECT name, state FROM ir_module_module WHERE state='installed' ORDER BY name;"

# Liệt kê tất cả databases
docker exec odoo-db psql -U odoo -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datistemplate=false;"
```

---

## Cấu trúc thư mục

```
odoo_tutor/
├── addons/
│   ├── oca-pos/                  # Các module OCA cho POS
│   └── pos_kitchen_screen_odoo/  # Module màn hình bếp (custom)
├── backups/                      # File .dump + .meta.txt
├── config/
│   └── odoo.conf                 # Cấu hình Odoo chính
├── scripts/
│   ├── safe_backup.sh            # Script backup
│   └── safe_restore.sh           # Script restore
├── docker-compose.yml
├── BACKUP_RESTORE.md
└── SETUP_EMPTY_DATABASE.md
```

---

## Workflow thường dùng

| Tình huống | Lệnh |
|---|---|
| Start | `docker compose up -d` |
| Stop | `docker compose down` |
| Xem logs Odoo | `docker compose logs -f odoo` |
| Xem logs DB | `docker compose logs -f db` |
| Backup DB hiện tại | `bash scripts/safe_backup.sh <db_name>` |
| Restore từ dump | `bash scripts/safe_restore.sh <target> <file> --yes` |
| Tạo DB mới trống | Xem mục "Tạo database mới" |
| Truy cập psql | `docker exec -it odoo-db psql -U odoo -d <db_name>` |
| Restart Odoo | `docker compose restart odoo` |
