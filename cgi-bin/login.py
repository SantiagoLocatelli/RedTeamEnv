#!/usr/bin/env python3
# Underworld Staff Portal - login handler (ORIGINAL system)
# ================================================================
#  INTENTIONALLY VULNERABLE TO SQL INJECTION.  ISOLATED LAB ONLY.
#  Realistic login: on success it only greets the user; on failure
#  it shows a generic message. It does NOT dump any table.
#  The database is misconfigured to print raw errors, so data is
#  extracted via ERROR-BASED injection, e.g. in the Keeper ID field:
#    ' AND 1=CAST((SELECT string_agg(username||':'||password_hash,', ')
#      FROM wardens) AS int)--
#  Do NOT deploy anywhere real.
# ================================================================
import os
import sys
import html
import urllib.parse

try:
    import psycopg2
except ImportError:
    print("Content-Type: text/html; charset=utf-8\n")
    print("<h1>psycopg2 not installed</h1><p>Run db/setup_db.sh on the VM.</p>")
    sys.exit(0)

DB = dict(host="127.0.0.1", port=5432, dbname="underworld",
          user="hades_app", password="styx")

length = int(os.environ.get("CONTENT_LENGTH") or 0)
fields = urllib.parse.parse_qs(sys.stdin.read(length))
username = fields.get("username", [""])[0]
password = fields.get("password", [""])[0]

print("Content-Type: text/html; charset=utf-8")
print()

print("""<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>House of Hades - Gate</title>
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@700&family=JetBrains+Mono&family=IBM+Plex+Sans&display=swap" rel="stylesheet">
<style>
 body{margin:0;background:#0A0604;color:#EEDFC6;font-family:'IBM Plex Sans',sans-serif;padding:3rem 1.25rem;text-align:center}
 .wrap{max-width:520px;margin:0 auto}
 h1{font-family:'Cinzel',serif;color:#E7C877;letter-spacing:.04em;font-size:26px;margin:0 0 .5rem}
 p{color:#A78A63}
 a{color:#C98A34}
 .deny h1{color:#A78A63}
 .err{text-align:left;background:#1a0a06;border:1px solid #A8340F;border-radius:8px;padding:1rem;color:#E5442A;font-family:'JetBrains Mono',monospace;font-size:.85rem;white-space:pre-wrap;margin-top:1rem}
</style></head><body><div class="wrap">""")

# VULNERABLE ON PURPOSE: both inputs concatenated straight into SQL,
# no parameterisation. Verbose errors below enable error-based extraction.
sql = ("SELECT username, email, role FROM wardens "
       "WHERE username = '" + username + "' "
       "AND password_hash = md5('" + password + "')")

try:
    conn = psycopg2.connect(**DB)
    cur = conn.cursor()
    cur.execute(sql)
    row = cur.fetchone()
    if row:
        # Realistic success: greet the authenticated keeper, nothing more.
        print('<h1>Access granted</h1>')
        print('<p>Welcome back, keeper <b>%s</b>.</p>' % html.escape(str(row[0])))
    else:
        print('<div class="deny"><h1>Access denied</h1>'
              '<p>The ferryman turns you away.</p>'
              '<p><a href="/login.html">Return to the gate</a></p></div>')
    cur.close()
    conn.close()
except Exception as e:
    # Verbose DB errors on purpose (enables error-based injection).
    print('<div class="err">%s</div>' % html.escape(str(e)))

print("</div></body></html>")
