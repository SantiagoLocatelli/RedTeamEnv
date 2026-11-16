# Attack plan — House of Hades

End-to-end structure of the engagement, mapped to the assessment's phases and the
technical decisions behind each one. Status: **[built]** in this repo / lab,
**[planned]** not yet implemented.

> ISOLATED LAB ONLY. Host-only network.

## Core idea

```
RECON -> SQLi (data) -> PHISHING (credential) -> APACHE CVE (access)
       -> PIVOT to internal network -> WORKSTATION -> ESCALATE -> EXFIL -> PAYLOAD
```

- **SQL injection gives data, not access** — it reveals *who* to phish.
- **The Apache CVE gives access, not credentials** — a foothold, not valid accounts.
- **Phishing bridges the two** — the harvested AD credential is used, from the
  foothold, to reach the internal network. Under SSO the portal credential is also
  the workstation credential.

## Network zones

```
[ External Kali ] 203.0.113.0/29 ──[ pfSense ]── [ Apache 10.1.1.0/28 ]  (DMZ, phases 1-4)
                                                         │
                                        [ Internal 192.168.1.0/24 ]  (phases 5+)
                                        - olympus-dc (target DC, olympus.net)        e.g. .100
                                        - hades-dc (email server, hades.underworld)
                                        - persephone-ws (joined to olympus.net)      e.g. .103
                                        - Splunk 192.168.1.6
```
Only the Apache gatehouse is reachable from outside. The internal zone is reached
only after a foothold on the gatehouse.

---

## Phase 1 — Watchful Gods (Reconnaissance)
- **Goal:** map the attack surface of the exposed gatehouse.
- **Technique:** `nmap -p- -sV` finds port 80 + `Apache/2.4.49`. `gobuster` on the
  root finds `login.html` + the `/cgi-bin/` dir (403). gobuster does not recurse,
  so run it again with `/cgi-bin/` as the base URL to enumerate the scripts
  (`login.py`, `admissions.py`); `admissions.py` needs a wordlist containing
  "admissions" (e.g. directory-list-2.3-medium).
- **Yields:** the injectable endpoint *and* the outdated Apache version.
- **Status:** target **[built]**.

## Phase 2 — Admissions of the Damned (SQL Injection)
- **Goal:** steal the staff directory.
- **Technique:** detect (`'` -> PostgreSQL error) -> enumerate with
  `information_schema` (discover `wardens` and its columns) -> UNION to dump.
- **Yields:** usernames + emails + roles = the phishing targeting list. No passwords
  (authentication is AD).
- **Status:** **[built]** (`admissions.py`).

## Phase 3 — False Messenger (Phishing)
- **Goal:** obtain a real employee's AD credential.
- **Technique:** a fake clone of the SSO portal is sent to a targeted warden (using
  the emails from Phase 2). The victim enters their real AD credential.
- **Yields:** a credential that works on the internal network (SSO: portal =
  workstation).
- **Status:** the **real** portal is **[built]** (`login.html` + LDAP bind to AD);
  the **fake clone** is **[planned]**.

## Phase 4 — Forgotten Gatehouse (Identify + Exploit the CVE)
- **Goal:** confirm the outdated software, then exploit it for a foothold.
- **Identify:** `curl -I` -> `Server: Apache/2.4.49` -> CVE-2021-41773 / 42013.
- **Exploit:** path traversal -> RCE via CGI (`.%2e/` or double-encoding), run through the
  Metasploit `apache_normalize_path_rce` module with a `meterpreter` payload. Lands as
  low-privileged `daemon`.
- **Yields:** a **meterpreter** foothold on the gatehouse (the C2 session the pivot rides).
- **Status:** vulnerable target **[built]** (Apache 2.4.49 + `mod_cgid` + `Require all granted`);
  exploitation done in the lab.

## Phase 5 — Breach of Hades (Pivot + RDP lateral)
- **Goal:** move from the foothold into the internal network and get an interactive
  session on persephone-ws.
- **Technique:** from the foothold, map the internal LAN with a fast ping sweep
  (`for i in $(seq 1 254); do ping -c1 -W1 192.168.1.$i | grep "bytes from"; done`) to find
  olympus-dc, persephone-ws and Splunk — a full nmap `/24` connect scan is too slow (~1h);
  ICMP can miss firewalled Windows hosts, so fall back to a `/dev/tcp` sweep of 445/3389.
  Then **pivot with meterpreter `portfwd`** (forward the ws 3389 to a local port on Kali —
  no SSH cred needed, it rides the existing C2) and RDP in as the phished `persephone`
  (NLA off + `/sec:tls`). Full runbook: `docs/phase5-6-pivot-escalation.md`.
- **Yields:** an interactive RDP session on persephone-ws as a normal domain user.
- **Status:** **[done in the lab]** (pivot + RDP lateral working).

## Phase 6 — Keys of the Gods (Privilege escalation)
- **Goal:** escalate on persephone-ws from a normal user to local admin / SYSTEM.
- **Technique:** abuse **AlwaysInstallElevated** — a malicious MSI (msfvenom) runs as
  SYSTEM via `msiexec` and adds a local admin; from local admin, dump creds and move
  toward olympus-dc. Full runbook: Step 5 of `docs/phase5-6-pivot-escalation.md`.
- **Yields:** local admin / SYSTEM on the workstation.
- **Status:** **[in progress]** (vector defined: AlwaysInstallElevated).

## Phase 7 — Stolen Relics (Exfiltration)
- **Goal:** steal the target data (photos of rocks) protected by an acrostic cipher.
- **Technique:** locate the files in the "Cretan Labyrinth" folder maze, decode the
  acrostic.
- **Status:** **[planned]**.

## Phase 8 — The Hephaestus Connection (Decipher the payload)
- **Goal:** analyse the images to recover the password that decrypts the folder
  holding the EXE payload (which was on the attack machine all along).
- **Status:** **[planned]**.

## Phase 9 — Curse of Kronos (Final payload)
- **Goal:** deliver a delayed payload with a countdown that shows an image and shuts
  the machine down.
- **Status:** **[planned]**.

---

## Architecture decisions (why it is coherent)

- **Authentication = Active Directory (SSO).** The portal does an LDAP bind to
  olympus-dc; it stores no passwords, so the login is **not** SQL-injectable. This
  is standard for internal corporate apps and is why phishing the portal yields a
  network-wide credential.
- **Application data = PostgreSQL.** Holds the directory and records; this is what
  SQL injection loots. The directory (emails) is the phishing targeting data.
- **Two vulnerabilities on one box, different layers.** SQL injection (application)
  gives data; the Apache CVE (server) gives access. They are complementary, not
  redundant.
- **The credential belongs on the workstation, not the web server.** An employee
  naturally has an account on their own Windows workstation (domain-joined), so the
  phished AD credential is used there after pivoting through the gatehouse.

## Current status

- **Built:** recon target, SQL injection on admissions, the real AD-authenticated
  portal, PostgreSQL directory, **olympus-dc** (target, `olympus.net`) and **persephone-ws** (joined to `olympus.net`, RDP enabled, `persephone` authorised); **hades-dc** (`hades.underworld`, email server) is a separate box.
- **In progress:** Phase 6 escalation (AlwaysInstallElevated) on persephone-ws; Phase 5 pivot + RDP lateral done.
- **Next:** finish Phase 6 escalation → the exfiltration chain (Phases 7-9).
