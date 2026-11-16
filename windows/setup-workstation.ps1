<#
  setup-workstation.ps1 - configure the Blue Team workstation (persephone-ws) for the
  Phase 5-6 RDP pivot: enable RDP, start the service, open the firewall, DISABLE NLA,
  authorise the RDP user, and plant the AlwaysInstallElevated misconfiguration (the
  Stage 6 local-privesc target).

  Run in an ELEVATED PowerShell on the workstation (VM console / noVNC), AFTER it is
  domain-joined to olympus.net and you have logged in once as the user so the profile
  exists.

  Why NLA is disabled: from a non-domain Kali the Kerberos KDC is not reachable through
  the portfwd tunnel (and Kerberos over a 127.0.0.1 forward breaks on SPN / clock skew),
  so the default NLA handshake hangs with "Cannot find KDC for realm". With NLA off, the
  pivot connects with `xfreerdp3 ... /sec:tls`. NLA-off RDP is a realistic weakness —
  note it in the report.

  ISOLATED LAB ONLY. Authorised assessment. Host-only network.
#>

# ---------------- CONFIG ----------------
$RdpUser    = "OLYMPUS\persephone"   # account allowed to RDP in (DOMAIN\user)
$Interface  = "Ethernet"             # NIC alias (run Get-NetAdapter to confirm)
$ForcePrivate = $true                # flip a Public profile to Private (firewall)
# ----------------------------------------

$ErrorActionPreference = "Stop"
function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[*]   $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[!]   $m" -ForegroundColor Yellow }

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this in an ELEVATED PowerShell (Administrator)."
}

# 1. Enable RDP
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Ok "RDP enabled (fDenyTSConnections = 0)"

# 2. RDP service automatic + started
Set-Service TermService -StartupType Automatic
if ((Get-Service TermService).Status -ne 'Running') { Start-Service TermService }
Ok "TermService: $((Get-Service TermService).Status), startup Automatic"

# 3. Firewall rule for RDP
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Ok "Firewall group 'Remote Desktop' enabled"

# 4. Disable NLA (so a non-domain Kali can connect with /sec:tls)
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 0
Ok "NLA disabled (UserAuthentication = 0)"

# 5. Authorise the RDP user (net localgroup is robust; Add-LocalGroupMember throws
#    'Object reference not set...' on domain accounts on some builds)
$grp = "Remote Desktop Users"
$already = (net localgroup $grp) -match [regex]::Escape($RdpUser)
if ($already) { Ok "$RdpUser already in '$grp'" }
else {
    cmd /c "net localgroup `"$grp`" `"$RdpUser`" /add" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "Added $RdpUser to '$grp'" }
    else { Warn "Could not add $RdpUser to '$grp' (exit $LASTEXITCODE) - add it manually" }
}

# 6. Network profile (Public breaks the inbound RDP rule)
$prof = Get-NetConnectionProfile -InterfaceAlias $Interface -ErrorAction SilentlyContinue
if ($prof) {
    Info "Network profile on $Interface = $($prof.NetworkCategory)"
    if ($prof.NetworkCategory -eq 'Public' -and $ForcePrivate) {
        Set-NetConnectionProfile -InterfaceAlias $Interface -NetworkCategory Private
        Ok "Switched $Interface profile Public -> Private"
    }
}

# 7. Plant the AlwaysInstallElevated misconfiguration (Stage 6 privesc target)
#    Vulnerable only when BOTH hives = 1: HKLM (machine-wide) + HKCU (per-user).
#    HKCU is per-user, so it must land in persephone's hive -- NOT the admin hive this
#    script runs under. A normal user cannot set it themselves (the Policies subtree is
#    admin-write-only -> 'access denied'); that is exactly why it is a valid finding --
#    it can only arrive via an admin/misconfig. We resolve persephone's SID and write
#    into her hive (HKEY_USERS\<SID>), loading NTUSER.DAT if she is not currently logged in.
#    (GPO User-config is the realistic alternative; here we plant it directly.)
$key = 'Software\Policies\Microsoft\Windows\Installer'

# HKLM -- single machine hive
New-Item "HKLM:\$key" -Force | Out-Null
Set-ItemProperty "HKLM:\$key" -Name AlwaysInstallElevated -Value 1 -Type DWord
Ok "HKLM AlwaysInstallElevated = 1"

# HKCU -- into persephone's hive, resolved by SID
$acct = $RdpUser                                             # OLYMPUS\persephone
$sid  = (New-Object System.Security.Principal.NTAccount($acct)).Translate(
            [System.Security.Principal.SecurityIdentifier]).Value
$uprofile = "C:\Users\$($acct.Split('\')[-1])"              # C:\Users\persephone
$loaded = $false
if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
    reg load "HKU\$sid" "$uprofile\NTUSER.DAT" | Out-Null   # requires the user logged OFF
    $loaded = $true
}
New-Item "Registry::HKEY_USERS\$sid\$key" -Force | Out-Null
Set-ItemProperty "Registry::HKEY_USERS\$sid\$key" -Name AlwaysInstallElevated -Value 1 -Type DWord
Ok "HKCU AlwaysInstallElevated = 1 (hive of $acct, SID $sid)"
if ($loaded) { [gc]::Collect(); Start-Sleep -Milliseconds 500; reg unload "HKU\$sid" | Out-Null }

# 8. Verify 3389 is listening
Start-Sleep -Seconds 1
if (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue) {
    Ok "3389 is LISTENING - from the gatehouse test: bash -c 'echo > /dev/tcp/<ws-ip>/3389'"
} else {
    Warn "3389 is NOT listening yet - re-check TermService / firewall."
}

Write-Host ""
Ok "Workstation ready. Connect from Kali through the portfwd:"
Write-Host "    xfreerdp3 /u:persephone /d:olympus.net /p:'<password>' /v:127.0.0.1:13389 /cert:ignore +clipboard /sec:tls"
Write-Host ""
Info "Recon as persephone (custom, NOT AV-flagged like winPEAS/PowerUp): powershell -ep bypass -File .\mini-powerup.ps1"
