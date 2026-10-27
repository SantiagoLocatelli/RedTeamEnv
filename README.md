# VictimWeb

Themed target web app for an **isolated** cybersecurity lab assessment
(Greek mythology / "House of Hades"), served by Apache 2.4.49 compiled
from source at `/opt/apache-2.4.49`.

> WARNING: Apache 2.4.49 is vulnerable (CVE-2021-41773 / CVE-2021-42013).
> Use only inside a host-only VM. Never expose it to the internet.

## Role in the assessment

- **Underworld Staff Portal** (`htdocs/login.html`) — the fake login used in
  Phase 3 "False Messenger" to demonstrate credential-harvesting risk.
- `cgi-bin/login.py` processes the POST and logs attempts to a local
  `harvest.log` (git-ignored) for lab review.
- A deliberately vulnerable database for the SQL-injection phase will be
  added next.

## Layout

| Folder | Destination on the VM |
|---|---|
| `htdocs/` | `/opt/apache-2.4.49/htdocs/` |
| `cgi-bin/` | `/opt/apache-2.4.49/cgi-bin/` |

## Deploy on the VM

```bash
cd ~
git clone https://github.com/USERNAME/VictimWeb.git   # first time
cd VictimWeb
# or to update:  git pull

sudo ./deploy.sh
```

## Demo credentials

`charon` / `ferryman` (themed demo, hardcoded in `cgi-bin/login.py`).

## Test

```bash
curl http://localhost/login.html
curl -X POST -d "username=charon&password=ferryman" http://localhost/cgi-bin/login.py
```
