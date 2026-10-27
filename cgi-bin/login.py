#!/usr/bin/env python3
# Underworld Staff Portal - login handler (ORIGINAL system)
# ================================================================
#  INTENTIONALLY VULNERABLE TO SQL INJECTION.  ISOLATED LAB ONLY.
#  Authenticates against the wardens table with a concatenated
#  query and prints raw DB errors, so BOTH UNION-based and
#  error-based injection can extract every user's data.
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
 body{margin:0;background:#0A0604;color:#EEDFC6;font-family:'IBM Plex Sans',sans-serif;padding:2.5rem 1.25rem}
 .wrap{max-width:720px;margin:0 auto}
 h1{font-family:'Cinzel',serif;color:#E7C877;letter-spacing:.04em;font-size:24px;margin:0 0 .6rem}
 a{color:#C98A34}
 table{width:100%;border-collapse:collapse;border:1px solid #3a2817;border-radius:10px;overflow:hidden;margin-top:1rem}
 th,td{text-align:left;padding:.6rem .8rem;border-bottom:1px solid #271a0e;font-size:.9rem}
 th{background:#160F09;font-family:'JetBrains Mono',monospace;font-size:10.5px;letter-spacing:.16em;text-transform:uppercase;color:#A78A63}
 td{font-family:'JetBrains Mono',monospace}
 .deny h1{color:#A78A63}
 .err{background:#1a0a06;border:1px solid #A8340F;border-radius:8px;padding:1rem;color:#E5442A;font-family:'JetBrains Mono',monospace;font-size:.85rem;white-space:pre-wrap;margin-top:1rem}
</style></head><body><div class="wrap">""")

# VULNERABLE ON PURPOSE: both inputs concatenated straight into SQL,
# no parameterisation. Enables UNION-based and error-based extraction.
sql = ("SELECT username, email, role FROM wardens "
       "WHERE username = '" + username + "' "
       "AND password_hash = md5('" + password + "')")

try:
    conn = psycopg2.connect(**DB)
    cur = conn.cursor()
    cur.execute(sql)
    rows = cur.fetchall()
    print("DEBUG rows:", rows, file=sys.stderr)
    if rows:
        print('<h1>Access granted</h1>')
        print('<table><tr><th>Keeper</th><th>Email</th><th>Role</th></tr>')
        for r in rows:
            cells = "".join("<td>%s</td>" % html.escape(str(c) if c is not None else "") for c in r)
            print("<tr>%s</tr>" % cells)
        print('</table>')
    else:
        print('<div class="deny"><h1>The ferryman turns you away.</h1>'
              '<p><a href="/login.html">Return to the gate</a></p></div>')
    cur.close()
    conn.close()
except Exception as e:
    # Verbose DB errors on purpose (enables error-based injection).
    print('<div class="err">%s</div>' % html.escape(str(e)))

print("</div></body></html>")
