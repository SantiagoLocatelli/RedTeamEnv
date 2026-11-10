#!/usr/bin/env python3
# Underworld Staff Portal - login handler (ORIGINAL system)
# ================================================================
#  Authentication is delegated to Active Directory (SSO) via an
#  LDAP bind. The portal stores NO passwords and does NOT query
#  the database for auth -> there is NO SQL injection here.
#  The same credential logs the user into their Windows workstation
#  (domain-joined). ISOLATED LAB ONLY.
#
#  Set AD_HOST / AD_DOMAIN below to your domain controller.
# ================================================================
import os
import sys
import html
import urllib.parse

# ---- Active Directory settings (point these at your Windows DC) ----
AD_HOST = "ldap://192.168.1.100"   # the Windows Server domain controller
AD_DOMAIN = "hades.underworld"         # AD domain / UPN suffix

try:
    from ldap3 import Server, Connection, ALL
except ImportError:
    print("Content-Type: text/html; charset=utf-8\n")
    print("<h1>ldap3 not installed</h1><p>Run: sudo apt install -y python3-ldap3</p>")
    sys.exit(0)

length = int(os.environ.get("CONTENT_LENGTH") or 0)
fields = urllib.parse.parse_qs(sys.stdin.read(length))
username = fields.get("username", [""])[0].strip()
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
 p{color:#A78A63} a{color:#C98A34}
 .deny h1{color:#A78A63}
</style></head><body><div class="wrap">""")


def authenticate(user, pwd):
    # Reject empty credentials: AD treats a simple bind with an empty
    # password as an *unauthenticated* bind, which would "succeed".
    if not user or not pwd:
        return False
    try:
        server = Server(AD_HOST, get_info=ALL)
        conn = Connection(server, user="%s@%s" % (user, AD_DOMAIN),
                          password=pwd, auto_bind=True)
        conn.unbind()
        return True
    except Exception:
        return False


if authenticate(username, password):
    print('<h1>Access granted</h1>')
    print('<p>Welcome back, keeper <b>%s</b>.</p>' % html.escape(username))
else:
    print('<div class="deny"><h1>Access denied</h1>'
          '<p>The ferryman turns you away.</p>'
          '<p><a href="/login.html">Return to the gate</a></p></div>')

print("</div></body></html>")
