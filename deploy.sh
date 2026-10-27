#!/usr/bin/env bash
# Despliega los archivos del repo en la instalacion de Apache 2.4.49.
# Uso (dentro de la VM):  sudo ./deploy.sh
set -e

APACHE="/opt/apache-2.4.49"

echo "[*] Copiando htdocs..."
cp htdocs/* "$APACHE/htdocs/"

echo "[*] Copiando cgi-bin..."
cp cgi-bin/* "$APACHE/cgi-bin/"

echo "[*] Permisos de ejecucion en los CGI..."
chmod 755 "$APACHE"/cgi-bin/*.py

echo "[*] Normalizando finales de linea (por si se editaron en Windows)..."
sed -i 's/\r$//' "$APACHE"/cgi-bin/*.py

echo "[*] Validando config y reiniciando..."
"$APACHE/bin/apachectl" -t
"$APACHE/bin/apachectl" -k restart

echo "[OK] Listo. Probar: curl http://localhost/login.html"
