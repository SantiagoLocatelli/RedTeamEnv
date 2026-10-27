#!/usr/bin/env python3
import os, sys, html, urllib.parse

length = int(os.environ.get("CONTENT_LENGTH") or 0)
data = urllib.parse.parse_qs(sys.stdin.read(length))
user = data.get("username", [""])[0]
pwd = data.get("password", [""])[0]

print("Content-Type: text/html; charset=utf-8")
print()

if user == "admin" and pwd == "lab123":
    print(f"<h1>Bienvenido, {html.escape(user)}</h1>")
else:
    print("<h1>Credenciales incorrectas</h1><a href='/login.html'>Volver</a>")
