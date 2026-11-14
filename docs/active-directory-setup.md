# Active Directory setup (Windows Server DC)

The staff portal authenticates against **Active Directory**, and the Windows
workstations are **domain-joined**, so one credential works on the portal and on the
workstation (SSO). This guide stands up a Windows Server domain controller, creates the
warden accounts, joins a workstation, and points the portal at the DC.

> ISOLATED LAB ONLY. Host-only network.
> Domain: **`hades.underworld`** · DC: **`192.168.1.100`** · Workstation: **`192.168.1.103`**.

## Automated setup

`windows/setup-dc.ps1` scripts this whole guide and records every run to a transcript
log. Edit the CONFIG block at the top (it already targets `hades.underworld` /
`192.168.1.100`), then, in an elevated PowerShell:

```powershell
.\setup-dc.ps1     # phase 1: network + AD DS + promotion (reboots)
# after the reboot:
.\setup-dc.ps1     # phase 2: creates the warden accounts
```

It is idempotent and self-detecting (skips existing users, knows which phase to run).
The manual steps below are the same commands, for reference.

## 1. Prerequisites

- A **Windows Server** VM (2019/2022) with a **static IP** (`192.168.1.100`).
- The internal Windows workstations will use this DC as their **DNS server**.

## 2. Install AD DS and promote to a domain controller

On the Windows Server, in an elevated PowerShell:

```powershell
# Install the AD Domain Services role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Create a brand-new forest / domain (reboots automatically)
Install-ADDSForest -DomainName "hades.underworld" -InstallDns -Force
```

After the reboot you have a domain `hades.underworld` with this server as the DC + DNS.

## 3. Create the warden accounts

All wardens are **normal** domain users (none is a domain admin). They share
`Ferryman1!` — **except `persephone`, the phishing victim, whose password is
`Demeter01!`**.

```powershell
$pw   = ConvertTo-SecureString "Ferryman1!" -AsPlainText -Force
$pwPs = ConvertTo-SecureString "Demeter01!" -AsPlainText -Force

New-ADUser -Name "Charon"     -SamAccountName "charon"     -UserPrincipalName "charon@hades.underworld" `
  -EmailAddress "charon@hades.underworld"     -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Cerberus"   -SamAccountName "cerberus"   -UserPrincipalName "cerberus@hades.underworld" `
  -EmailAddress "warden@hades.underworld"     -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Minos"      -SamAccountName "minos"      -UserPrincipalName "minos@hades.underworld" `
  -EmailAddress "minos@hades.underworld"      -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Hades"      -SamAccountName "hades"      -UserPrincipalName "hades@hades.underworld" `
  -EmailAddress "lord@hades.underworld"       -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Persephone" -SamAccountName "persephone" -UserPrincipalName "persephone@hades.underworld" `
  -EmailAddress "persephone@hades.underworld" -AccountPassword $pwPs -Enabled $true
```

> **Password policy:** AD enforces complexity by default, so `ferryman` is rejected —
> that is why the example uses `Ferryman1!`. For a lab you may relax the policy
> (`Set-ADDefaultDomainPasswordPolicy`) if you want weaker passwords, but keep the
> portal and workstation passwords identical so SSO holds.

## 4. Join a Windows workstation to the domain

On the Blue Team workstation (example IP `192.168.1.103`):

1. Set its **DNS server** to the DC's IP (`192.168.1.100`).
2. Join the domain and reboot:

```powershell
Add-Computer -DomainName "hades.underworld" -Credential (Get-Credential) -Restart
```

Now a warden can log into the workstation with `HADES\persephone` + their password —
the **same** credential the portal uses.

## 5. Point the portal at the DC

In `cgi-bin/login.py` on the Apache server (already set to these values):

```python
AD_HOST = "ldap://192.168.1.100"   # your DC's IP
AD_DOMAIN = "hades.underworld"
```

The Apache (gatehouse) server must be able to reach the DC on **TCP 389** (LDAP) or
**636** (LDAPS). If the firewall segments DMZ from internal, allow the portal → DC auth
traffic (this is a normal real-world allowance; pfSense alias `AD_DC_Ports` + rule
DMZ → DC already covers it).

## 6. Test

- From the portal (`login.html`), log in with `charon` / `Ferryman1!` → "Access granted".
- `persephone` / `Demeter01!` → "Access granted" (this is the phished account).
- A wrong password → "Access denied".
- From the gatehouse: `python3 tools/ad_bind_test.py 192.168.1.100 hades.underworld persephone 'Demeter01!'` → `BIND OK`.

## Role in the attack chain

- The portal no longer stores passwords, so there is **no SQL injection on the login**
  and no hashes to crack.
- The attack path is: SQL injection on **admissions** → harvest the staff directory
  (usernames + emails) → **phish** `persephone` with a fake copy of this portal → the
  victim types her **AD credential** → that credential RDPs into her **domain-joined
  workstation** (`192.168.1.103`) via the Phase 6 `portfwd` pivot. See the main
  `README.md` and `docs/phase6-pivot.md`.
