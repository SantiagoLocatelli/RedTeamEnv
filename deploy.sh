#!/usr/bin/env bash
# Deploys the repo files into the Apache 2.4.49 lab install.
# Usage (inside the VM):  sudo ./deploy.sh
# Custom Apache path:     sudo APACHE=/path/to/apache ./deploy.sh
set -e

APACHE="${APACHE:-/opt/apache-2.4.49}"

echo "[*] Copying htdocs..."
cp htdocs/* "$APACHE/htdocs/"

echo "[*] Copying cgi-bin..."
cp cgi-bin/* "$APACHE/cgi-bin/"

echo "[*] Setting execute permissions on CGI scripts..."
chmod 755 "$APACHE"/cgi-bin/*.py

echo "[*] Normalising line endings (in case files were edited on Windows)..."
sed -i 's/\r$//' "$APACHE"/cgi-bin/*.py

echo "[*] Validating config and restarting..."
"$APACHE/bin/apachectl" -t
"$APACHE/bin/apachectl" -k restart

echo "[OK] Done. Test: curl http://localhost/login.html"
