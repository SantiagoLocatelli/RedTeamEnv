#!/usr/bin/env bash
# install_apache.sh - build Apache 2.4.49 from source for the lab.
# ISOLATED LAB ONLY. Apache 2.4.49 is vulnerable (CVE-2021-41773 / 42013) by design.
# Usage:  sudo ./install_apache.sh
set -e

VERSION="2.4.49"
PREFIX="${APACHE:-/opt/apache-${VERSION}}"
SRC="https://archive.apache.org/dist/httpd/httpd-${VERSION}.tar.gz"
BUILD_DIR="/tmp/apache-build"
CONF="${PREFIX}/conf/httpd.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Run with sudo:  sudo ./install_apache.sh"
  exit 1
fi

if [ -x "${PREFIX}/bin/httpd" ]; then
  echo "[*] Apache already installed at ${PREFIX}:"
  "${PREFIX}/bin/httpd" -v
  echo "[*] Re-running will rebuild and overwrite it. Continuing..."
fi

echo "[*] Installing build dependencies..."
apt-get update
apt-get install -y build-essential wget \
  libapr1-dev libaprutil1-dev libpcre2-dev libssl-dev

echo "[*] Downloading Apache ${VERSION} source..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
wget -q --show-progress -O "httpd-${VERSION}.tar.gz" "${SRC}"
tar -xzf "httpd-${VERSION}.tar.gz"
cd "httpd-${VERSION}"

echo "[*] Configuring (CGI enabled so the .py scripts run)..."
./configure --prefix="${PREFIX}" --enable-so --enable-rewrite --enable-cgid

echo "[*] Building (this can take a few minutes)..."
make -j"$(nproc)"

echo "[*] Installing to ${PREFIX}..."
make install

echo "[*] Enabling mod_cgid in httpd.conf..."
# uncomment it if present-but-commented
sed -i 's|^#\s*\(LoadModule cgid_module modules/mod_cgid.so\)|\1|' "${CONF}"
# add it if missing entirely
grep -q "^LoadModule cgid_module" "${CONF}" || \
  echo 'LoadModule cgid_module modules/mod_cgid.so' >> "${CONF}"

echo "[*] Setting ServerName (avoids the FQDN warning)..."
grep -q "^ServerName " "${CONF}" || echo 'ServerName localhost:80' >> "${CONF}"

echo "[*] Validating configuration..."
"${PREFIX}/bin/apachectl" -t

echo ""
echo "[OK] Apache ${VERSION} installed:"
"${PREFIX}/bin/httpd" -v
echo ""
echo "Next steps:"
echo "  sudo ./deploy.sh          # copy the web + CGI into Apache"
echo "  sudo ./db/setup_db.sh     # PostgreSQL + seed data"
echo "  sudo ${PREFIX}/bin/apachectl -k start"
