#!/usr/bin/env python3
# Underworld Admissions Registry — public soul search
# ================================================================
#  INTENTIONALLY VULNERABLE TO SQL INJECTION.  ISOLATED LAB ONLY.
#  The search query concatenates user input straight into SQL and
#  prints raw DB errors, so error-based, boolean and UNION-based
#  injection all work. Do NOT deploy anywhere real.
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

# --- read the search term from GET (?q=...) ---
qs = urllib.parse.parse_qs(os.environ.get("QUERY_STRING", ""))
q = qs.get("q", [""])[0]

print("Content-Type: text/html; charset=utf-8")
print()

PAGE_HEAD = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Underworld Admissions Registry</title>
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@700;900&family=JetBrains+Mono&family=IBM+Plex+Sans&display=swap" rel="stylesheet">
<style>
 body{margin:0;background:#0A0604;color:#EEDFC6;font-family:'IBM Plex Sans',sans-serif;padding:2rem 1.25rem}
 .wrap{max-width:820px;margin:0 auto}
 h1{font-family:'Cinzel',serif;color:#C98A34;letter-spacing:.04em;text-transform:uppercase;font-size:28px;margin:0 0 4px}
 .sub{font-family:'JetBrains Mono',monospace;font-size:11px;letter-spacing:.24em;text-transform:uppercase;color:#6E5636;margin-bottom:24px}
 form{display:flex;gap:10px;margin-bottom:24px}
 input{flex:1;padding:.7rem .8rem;background:#080402;border:1px solid #3E2A16;border-radius:8px;color:#EEDFC6;font-family:'JetBrains Mono',monospace}
 input:focus{outline:none;border-color:#C98A34}
 button{padding:.7rem 1.3rem;border:none;border-radius:8px;background:linear-gradient(180deg,#FAC947,#7D5A24);color:#1a1006;font-family:'Cinzel',serif;font-weight:700;letter-spacing:.08em;text-transform:uppercase;cursor:pointer}
 table{width:100%;border-collapse:collapse;border:1px solid #3E2A16;border-radius:10px;overflow:hidden}
 th,td{text-align:left;padding:.65rem .8rem;border-bottom:1px solid #28190D;font-size:.92rem}
 th{background:#150E09;font-family:'JetBrains Mono',monospace;font-size:10.5px;letter-spacing:.18em;text-transform:uppercase;color:#A78A63}
 td{font-family:'JetBrains Mono',monospace;color:#EEDFC6}
 .err{background:#1a0a06;border:1px solid #A8340F;border-radius:8px;padding:1rem;color:#E5442A;font-family:'JetBrains Mono',monospace;font-size:.85rem;white-space:pre-wrap}
 .count{font-family:'JetBrains Mono',monospace;font-size:11px;color:#6E5636;margin-bottom:10px}
</style></head><body><div class="wrap">
<h1>Underworld Admissions Registry</h1>
<div class="sub">House of Hades &middot; Soul Lookup</div>
<form method="GET" action="/cgi-bin/admissions.py">
 <input type="text" name="q" placeholder="Search souls by name..." value="%s">
 <button type="submit">Search</button>
</form>"""

print(PAGE_HEAD % html.escape(q, quote=True))

if q:
    # VULNERABLE ON PURPOSE: raw string concatenation, no parameterisation.
    sql = "SELECT full_name, realm_of_origin, crime FROM souls WHERE full_name ILIKE '%" + q + "%'"
    try:
        conn = psycopg2.connect(**DB)
        cur = conn.cursor()
        cur.execute(sql)
        rows = cur.fetchall()
        print('<div class="count">%d record(s) returned</div>' % len(rows))
        print("<table><tr><th>Name</th><th>Realm of origin</th><th>Crime</th></tr>")
        for r in rows:
            cells = "".join("<td>%s</td>" % html.escape(str(c) if c is not None else "") for c in r)
            print("<tr>%s</tr>" % cells)
        print("</table>")
        cur.close()
        conn.close()
    except Exception as e:
        # Verbose DB errors on purpose (enables error-based injection).
        print('<div class="err">%s</div>' % html.escape(str(e)))

print("</div></body></html>")
