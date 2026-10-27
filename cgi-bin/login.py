#!/usr/bin/env python3
# Underworld Staff Portal - login handler
# ISOLATED CYBERSECURITY LAB ONLY (host-only network). Not for production use.
# Phase 3 "False Messenger": demonstrates credential-harvesting risk.
# Submitted attempts are written to a local log so the exercise can be reviewed.

import os
import sys
import html
import datetime
import urllib.parse

LOG_FILE = os.path.join(os.path.dirname(__file__), "harvest.log")
# Demo credentials for the themed portal.
VALID_USER = "charon"
VALID_PASS = "ferryman"

length = int(os.environ.get("CONTENT_LENGTH") or 0)
fields = urllib.parse.parse_qs(sys.stdin.read(length))
username = fields.get("username", [""])[0]
password = fields.get("password", [""])[0]

# Record the attempt (lab review only).
try:
    stamp = datetime.datetime.now().isoformat(timespec="seconds")
    src = os.environ.get("REMOTE_ADDR", "-")
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(f"{stamp}\t{src}\t{username}\t{password}\n")
except OSError:
    pass

print("Content-Type: text/html; charset=utf-8")
print()

if username == VALID_USER and password == VALID_PASS:
    print(f"<h1>Welcome, keeper {html.escape(username)}. The gates open.</h1>")
else:
    print("<h1>The ferryman turns you away.</h1>"
          "<p><a href='/login.html'>Return to the gate</a></p>")
