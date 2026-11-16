# Active Directory setup (Olympus domain controller)

The environment now has **two** domain controllers:

- **olympus-dc** — domain **`olympus.net`**. The **target**. The blue-network Windows
  workstation (`persephone-ws`) is domain-joined here, and the staff portal
  authenticates against it. **This guide builds this DC.**
- **hades-dc** — domain `hades.underworld`. Hosts the **email server**. Separate box,
  **not covered here** (its config is out of scope).

User **emails stay `@hades.underworld`** (the mailboxes live on the Hades mail server),
even though the **accounts and authentication live in `olympus.net`**. So UPN and
email deliberately differ — e.g. `persephone@olympus.net` (login) vs
`persephone@hades.underworld` (mailbox). That split is the whole point: the phished
`@hades.underworld` address is the *targeting* data; the credential the victim types is
their **Olympus** AD credential, which is what logs into the Olympus-joined workstation.

> ISOLATED LAB ONLY. Host-only network.
> Domain: **`olympus.net`** · DC: **olympus-dc** · Workstation: **persephone-ws**.
> IPs vary by environment — see the naming note in `handoff-estado-lab.md`. Examples
> below use olympus-dc = `192.168.1.100`, persephone-ws = `192.168.1.103`.

## Automated setup

`windows/setup-dc.ps1` scripts this whole guide and records every run to a transcript
log. Edit the CONFIG block at the top (it already targets `olympus.net` / NetBIOS
`OLYMPUS`), then, in an elevated PowerShell:

```powershell
.\setup-dc.ps1     # phase 1: network + AD DS + promotion (reboots)
# after the reboot:
.\setup-dc.ps1     # phase 2: creates the warden accounts
```

It is idempotent and self-detecting (skips existing users, knows which phase to run).
The manual steps below are the same commands, for reference.

## 1. Prerequisites

- A **Windows Server** VM (2019/2022) with a **static IP** (olympus-dc; example `192.168.1.100`).
- persephone-ws will use olympus-dc as its **DNS server**.

## 2. Install AD DS and promote to a domain controller

On olympus-dc, in an elevated PowerShell:

```powershell
# Install the AD Domain Services role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Create a brand-new forest / domain (reboots automatically)
Install-ADDSForest -DomainName "olympus.net" -InstallDns -Force
```

After the reboot you have a domain `olympus.net` with this server as the DC + DNS.

## 3. Create the warden accounts

All wardens are **normal** domain users (none is a domain admin). They share
`Ferryman1!` — **except `persephone`, the phishing victim, whose password is
`Demeter01!`**. Note the **UPN is `@olympus.net`** while the **EmailAddress stays
`@hades.underworld`**:

```powershell
$pw   = ConvertTo-SecureString "Ferryman1!" -AsPlainText -Force
$pwPs = ConvertTo-SecureString "Demeter01!" -AsPlainText -Force

New-ADUser -Name "Charon"     -SamAccountName "charon"     -UserPrincipalName "charon@olympus.net" `
  -EmailAddress "charon@hades.underworld"     -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Cerberus"   -SamAccountName "cerberus"   -UserPrincipalName "cerberus@olympus.net" `
  -EmailAddress "warden@hades.underworld"     -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Minos"      -SamAccountName "minos"      -UserPrincipalName "minos@olympus.net" `
  -EmailAddress "minos@hades.underworld"      -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Hades"      -SamAccountName "hades"      -UserPrincipalName "hades@olympus.net" `
  -EmailAddress "lord@hades.underworld"       -AccountPassword $pw   -Enabled $true
New-ADUser -Name "Persephone" -SamAccountName "persephone" -UserPrincipalName "persephone@olympus.net" `
  -EmailAddress "persephone@hades.underworld" -AccountPassword $pwPs -Enabled $true
```

> **Password policy:** AD enforces complexity by default, so `ferryman` is rejected —
> that is why the example uses `Ferryman1!`. For a lab you may relax the policy
> (`Set-ADDefaultDomainPasswordPolicy`), but keep the portal and workstation passwords
> identical so SSO holds.

## 4. Join persephone-ws to the domain

On the Blue Team workstation (persephone-ws; example IP `192.168.1.103`):

1. Set its **DNS server** to olympus-dc's IP.
2. Join the domain and reboot:

```powershell
Add-Computer -DomainName "olympus.net" -Credential (Get-Credential) -Restart
```

Now a warden logs into the workstation with `OLYMPUS\persephone` + their password —
the **same** credential the portal uses.

## 5. Point the portal at olympus-dc

In `cgi-bin/login.py` on the gatehouse (already set to these values):

```python
AD_HOST = "ldap://192.168.1.100"   # olympus-dc — set to your environment's IP
AD_DOMAIN = "olympus.net"
```

The gatehouse must reach olympus-dc on **TCP 389** (LDAP) / **636** (LDAPS). If the
firewall segments DMZ from internal, allow the portal → olympus-dc auth traffic
(pfSense alias `AD_DC_Ports` + rule DMZ → DC already covers it).

## 6. Test

- From the portal (`login.html`): `charon` / `Ferryman1!` → "Access granted".
- `persephone` / `Demeter01!` → "Access granted" (the phished account).
- A wrong password → "Access denied".
- From the gatehouse: `python3 tools/ad_bind_test.py <olympus-dc-ip> olympus.net persephone 'Demeter01!'` → `BIND OK`.

## Role in the attack chain

- The portal stores no passwords (LDAP bind to olympus-dc), so there is **no SQL
  injection on the login** and no hashes to crack.
- Path: SQL injection on **admissions** → harvest the staff directory (usernames +
  `@hades.underworld` emails) → **phish** `persephone` with a fake copy of this portal →
  the victim types her **Olympus** AD credential → that credential RDPs into
  `persephone-ws` (Olympus-joined) via the Phase 5 pivot. See `README.md` and
  `docs/phase5-6-pivot-escalation.md`.
- **hades-dc** (the email server's domain) is where the phishing *lands* as mail; the
  foothold and lateral movement happen against **olympus.net**.
