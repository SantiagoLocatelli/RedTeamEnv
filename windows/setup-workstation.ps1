<#
  setup-workstation.ps1 - provision persephone-ws from a FRESH Windows VM, end to end.

  2-phase, self-resuming (domain join forces a reboot; a linear script can't span it):

    PHASE A (you run once, elevated):
        set DNS->DC + static IP -> copy self to C:\ProgramData\ws-setup ->
        register a SYSTEM startup task to resume -> join olympus.net -> reboot.
    PHASE B (runs AUTOMATICALLY after the reboot, as SYSTEM via that task):
        wait for the DC -> create persephone's profile non-interactively ->
        enable RDP + disable NLA + authorise persephone ->
        plant AlwaysInstallElevated (HKLM + HKCU) -> verify 3389 -> self-clean.

  Phase is auto-detected by domain membership. Force with:  -Phase A   or   -Phase B
  Logs: C:\ProgramData\ws-setup\setup-ws-phase<A|B>.log

  ISOLATED LAB ONLY. Authorised TAFE Cert IV assessment. Host-only network.
  NLA is disabled on purpose: from a non-domain Kali the KDC is unreachable through the
  portfwd, so the pivot connects with `xfreerdp3 ... /sec:tls`. Note it as a finding.
#>
param(
    [ValidateSet('Auto','A','B')]
    [string]$Phase = 'Auto'
)

# ---------------- CONFIG ----------------
$Domain      = 'olympus.net'
$DCip        = '192.168.1.100'
$IP          = '192.168.1.110'
$Prefix      = 24
$Gateway     = '192.168.1.1'
$Interface   = 'Ethernet'                 # run Get-NetAdapter to confirm the alias
$RdpUser     = 'OLYMPUS\persephone'
$RdpPass     = 'Demeter01!'               # lab cred - used to create persephone's profile
$StateDir    = 'C:\ProgramData\ws-setup'
$ScriptLocal = Join-Path $StateDir 'setup-workstation.ps1'
$ResumeTask  = 'WsSetupResume'
$key         = 'Software\Policies\Microsoft\Windows\Installer'
# ----------------------------------------

$ErrorActionPreference = 'Stop'
function Ok($m){   Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[*]   $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[!]   $m" -ForegroundColor Yellow }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this in an ELEVATED PowerShell (Administrator)."
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

# ---- phase detection ----
$cs = Get-CimInstance Win32_ComputerSystem
$joined = $cs.PartOfDomain -and ($cs.Domain -eq $Domain)
if ($Phase -eq 'Auto') { $Phase = if ($joined) { 'B' } else { 'A' } }
Start-Transcript -Path (Join-Path $StateDir "setup-ws-phase$Phase.log") -Append | Out-Null
Info "Phase $Phase  (joined=$joined, domain=$($cs.Domain))"

# =======================================================================
#  PHASE A - network + domain join + schedule resume + reboot
# =======================================================================
if ($Phase -eq 'A') {

    # 1. DNS -> DC (required for domain discovery)
    try { Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses $DCip; Ok "DNS on $Interface -> $DCip" }
    catch { throw "Could not set DNS on '$Interface' ($_). Run Get-NetAdapter and fix the `$Interface alias." }

    # 2. static IP (idempotent)
    if (-not (Get-NetIPAddress -InterfaceAlias $Interface -IPAddress $IP -ErrorAction SilentlyContinue)) {
        try { New-NetIPAddress -InterfaceAlias $Interface -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $Gateway | Out-Null
              Ok "Static IP $IP/$Prefix gw $Gateway" }
        catch { Warn "Could not set static IP ($_). Continuing - set it manually if the join fails." }
    } else { Ok "Static IP $IP already present" }

    # 3. domain-join credential (prompted, NOT hardcoded - repo is public)
    Info "Enter a domain account allowed to join the domain (e.g. hades):"
    $jc = Get-Credential -Message "Domain-join account for $Domain"

    # 4. copy self locally + register SYSTEM startup task to run Phase B after reboot
    Copy-Item -Path $PSCommandPath -Destination $ScriptLocal -Force
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptLocal`" -Phase B"
    $trg = New-ScheduledTaskTrigger -AtStartup
    $pr  = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $ResumeTask -Action $act -Trigger $trg -Principal $pr -Force | Out-Null
    Ok "Resume task '$ResumeTask' registered (fires Phase B at next boot)"

    # 5. join + reboot  (resume task runs Phase B automatically)
    Info "Joining $Domain and rebooting - Phase B will continue on its own..."
    Stop-Transcript | Out-Null
    Add-Computer -DomainName $Domain -Credential $jc -Restart -Force
    return
}

# =======================================================================
#  PHASE B - profile + RDP + flags  (runs as SYSTEM after the reboot)
# =======================================================================
if ($Phase -eq 'B') {

    # 0a. wait for the DC (AtStartup can fire before the network is up)
    Info "Waiting for DC $DCip (445)..."
    $w = 0
    while (-not (Test-NetConnection $DCip -Port 445 -InformationLevel Quiet) -and $w -lt 120) { Start-Sleep 5; $w += 5 }
    if ($w -ge 120) { Warn "DC not reachable after ${w}s - SID resolve / profile logon may fail." } else { Ok "DC reachable" }

    # 0b. ensure persephone's profile exists (NTUSER.DAT) - the HKCU plant needs it.
    #     Created non-interactively by running a one-shot task AS persephone (password logon).
    $uname    = $RdpUser.Split('\')[-1]
    $uprofile = "C:\Users\$uname"
    if (-not (Test-Path "$uprofile\NTUSER.DAT")) {
        Info "Creating $RdpUser profile non-interactively..."
        try {
            $pact = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit'
            Register-ScheduledTask -TaskName 'WsInitProfile' -Action $pact `
                -User $RdpUser -Password $RdpPass -RunLevel Limited -Force | Out-Null
            Start-ScheduledTask -TaskName 'WsInitProfile'
            $p = 0
            while (-not (Test-Path "$uprofile\NTUSER.DAT") -and $p -lt 60) { Start-Sleep 3; $p += 3 }
            Unregister-ScheduledTask -TaskName 'WsInitProfile' -Confirm:$false
        } catch { Warn "Profile-creation task failed ($_)." }
        if (Test-Path "$uprofile\NTUSER.DAT") { Ok "Profile created: $uprofile" }
        else { Warn "Profile NOT created - HKCU plant will fail. Check $RdpUser / password / DC." }
    } else { Ok "Profile already exists: $uprofile" }

    # 1. enable RDP
    Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    Ok "RDP enabled (fDenyTSConnections = 0)"

    # 2. RDP service automatic + started
    Set-Service TermService -StartupType Automatic
    if ((Get-Service TermService).Status -ne 'Running') { Start-Service TermService }
    Ok "TermService: $((Get-Service TermService).Status), startup Automatic"

    # 3. firewall
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Ok "Firewall group 'Remote Desktop' enabled"

    # 3b. allow inbound ICMPv4 echo (ping) on ALL profiles - Domain included.
    #     This box is domain-joined => its active firewall profile on the internal
    #     net is *Domain*. The built-in FPS-ICMP4-ERQ-In is often scoped to
    #     Private/Public only, so just enabling it leaves the host DEAD to the
    #     internal ping-sweep recon (Step 2). Force a rule that covers Domain too.
    Get-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -ErrorAction SilentlyContinue |
        Set-NetFirewallRule -Profile Any -Enabled True -ErrorAction SilentlyContinue
    if (-not (Get-NetFirewallRule -Name 'Lab-ICMP4-In' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'Lab-ICMP4-In' -DisplayName 'Lab ICMPv4 Echo In' `
            -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow -Profile Any | Out-Null
    }
    Ok "ICMPv4 echo (ping) allowed inbound on all profiles (Domain included)"

    # 4. disable NLA (non-domain Kali connects with /sec:tls)
    Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 0
    Ok "NLA disabled (UserAuthentication = 0)"

    # 5. authorise the RDP user
    $grp = "Remote Desktop Users"
    if ((net localgroup $grp) -match [regex]::Escape($RdpUser)) { Ok "$RdpUser already in '$grp'" }
    else {
        cmd /c "net localgroup `"$grp`" `"$RdpUser`" /add" | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "Added $RdpUser to '$grp'" } else { Warn "Could not add $RdpUser to '$grp' (exit $LASTEXITCODE)" }
    }

    # 6. network profile (Public breaks inbound RDP)
    $prof = Get-NetConnectionProfile -InterfaceAlias $Interface -ErrorAction SilentlyContinue
    if ($prof -and $prof.NetworkCategory -eq 'Public') {
        Set-NetConnectionProfile -InterfaceAlias $Interface -NetworkCategory Private
        Ok "Switched $Interface profile Public -> Private"
    } elseif ($prof) { Ok "Network profile = $($prof.NetworkCategory)" }

    # 7. plant AlwaysInstallElevated - BOTH hives = 1
    New-Item "HKLM:\$key" -Force | Out-Null
    Set-ItemProperty "HKLM:\$key" -Name AlwaysInstallElevated -Value 1 -Type DWord
    Ok "HKLM AlwaysInstallElevated = 1"

    $sid = (New-Object System.Security.Principal.NTAccount($RdpUser)).Translate(
               [System.Security.Principal.SecurityIdentifier]).Value
    $loaded = $false
    if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
        reg load "HKU\$sid" "$uprofile\NTUSER.DAT" | Out-Null       # persephone logged OFF
        $loaded = $true
    }
    New-Item "Registry::HKEY_USERS\$sid\$key" -Force | Out-Null
    Set-ItemProperty "Registry::HKEY_USERS\$sid\$key" -Name AlwaysInstallElevated -Value 1 -Type DWord
    Ok "HKCU AlwaysInstallElevated = 1 (hive of $RdpUser, SID $sid)"
    if ($loaded) { [gc]::Collect(); Start-Sleep -Milliseconds 500; reg unload "HKU\$sid" | Out-Null }

    # 8. verify 3389
    Start-Sleep 1
    if (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue) { Ok "3389 is LISTENING" }
    else { Warn "3389 NOT listening - re-check TermService / firewall." }

    # 9. remove the resume task (one-shot)
    Unregister-ScheduledTask -TaskName $ResumeTask -Confirm:$false -ErrorAction SilentlyContinue
    Ok "Provisioning complete - resume task removed."

    Stop-Transcript | Out-Null
    Write-Host ""
    Ok "persephone-ws ready. From Kali via the portfwd:"
    Write-Host "    xfreerdp3 /u:persephone /d:$Domain /p:'$RdpPass' /v:127.0.0.1:13389 /cert:ignore +clipboard /sec:tls"
    return
}
