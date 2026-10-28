#!/usr/bin/env bash
# Underworld Admissions DB setup — Ubuntu / PostgreSQL
# ISOLATED CYBERSECURITY LAB ONLY.
# Installs PostgreSQL + psycopg2, creates the app role and database,
# loads the schema, and grants the (over-privileged) read access that
# makes the UNION-based injection exercise work.
#
# Usage (inside the VM):  sudo ./db/setup_db.sh
set -e

APP_ROLE="hades_app"
APP_PASS="styx"
DB_NAME="underworld"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "[*] Installing PostgreSQL and psycopg2..."
apt update
apt install -y postgresql postgresql-contrib python3-psycopg2 python3-ldap3

echo "[*] Ensuring PostgreSQL is running..."
systemctl enable --now postgresql

echo "[*] Creating role '$APP_ROLE' if missing..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$APP_ROLE') THEN
    CREATE ROLE $APP_ROLE LOGIN PASSWORD '$APP_PASS';
  END IF;
END \$\$;
SQL

echo "[*] Creating database '$DB_NAME' if missing..."
sudo -u postgres psql -v ON_ERROR_STOP=1 -tc \
  "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
  sudo -u postgres createdb -O "$APP_ROLE" "$DB_NAME"

echo "[*] Loading schema and seed data..."
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" < "$HERE/schema.sql"

echo "[*] Granting read access to '$APP_ROLE' (intentional over-privilege)..."
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" <<SQL
GRANT USAGE ON SCHEMA public TO $APP_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $APP_ROLE;
SQL

echo "[*] Verifying connection as app role over TCP..."
PGPASSWORD="$APP_PASS" psql -h 127.0.0.1 -U "$APP_ROLE" -d "$DB_NAME" \
  -c "SELECT count(*) AS souls FROM souls;" || {
    echo "[!] TCP login failed. Check pg_hba.conf allows md5/scram for 127.0.0.1/32."
    exit 1
  }

echo "[OK] Database '$DB_NAME' ready. App role: $APP_ROLE / $APP_PASS"
echo "     Test the vulnerable page:  http://localhost/cgi-bin/admissions.py?q=sisyphus"
