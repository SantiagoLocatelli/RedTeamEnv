<#
  setup-dc.ps1 - House of Hades lab Domain Controller setup (replicable record).
  ISOLATED LAB ONLY. Authorised assessment.

  Automates: static IP + DNS, AD DS role, promotion to a new forest, and the
  warden accounts. Every run is recorded to a transcript log next to this script.

  Promotion REBOOTS the machine, so this is two-phase and self-detecting:
    1. First run  -> configures network, installs AD DS, promotes (then reboots).
    2. Run it AGAIN after the reboot -> creates the warden users.

  Run in an ELEVATED PowerShell:  .\setup-dc.ps1
  (If blocked:  Set-ExecutionPolicy -Scope Process Bypass -Force)
#>

# ============================ CONFIG (edit me) ============================
$DomainName     = "hades.underworld"        # AD domain (DNSRoot)
$NetBIOSName    = "HADES"              # short domain name
$DsrmPassword   = "DsrmP@ss-2026!"     # Directory Services Restore Mode password
$UserPassword   = "Ferryman1!"         # DEFAULT warden password (per-warden override via Pass=)

$ConfigureIP    = $true                # set to $false if the IP/DNS is already set
$StaticIP       = "192.168.1.100"
$PrefixLength   = 24
$Gateway        = "192.168.1.1"
$InterfaceAlias = "Ethernet"           # check with: Get-NetIPConfiguration

# wardens - must match the usernames in db/schema.sql
$Wardens = @(
  @{ Name = "Charon";   Sam = "charon";   Email = "charon@hades.underworld" },
  @{ Name = "Cerberus"; Sam = "cerberus"; Email = "warden@hades.underworld" },
  @{ Name = "Minos";    Sam = "minos";    Email = "minos@hades.underworld"  },
  @{ Name = "Persephone";    Sam = "persephone";    Email = "persephone@hades.underworld"; Pass = "Demeter01!" },
  @{ Name = "Hades";    Sam = "hades";    Email = "lord@hades.underworld"   }
)
# =========================================================================

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $PSScriptRoot "setup-dc-$stamp.log") -Append | Out-Null

# Detect whether the domain is already up (i.e. we are the post-reboot run).
$adReady = $false
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Get-ADDomain -ErrorAction Stop | Out-Null
    $adReady = $true
} catch { $adReady = $false }

if (-not $adReady) {
    Write-Host "[*] PHASE 1 - network + AD DS install + promotion (the machine will REBOOT)" -ForegroundColor Cyan

    if ($ConfigureIP) {
        Write-Host "[*] Setting static IP $StaticIP/$PrefixLength on '$InterfaceAlias'..."
        if (-not (Get-NetIPAddress -IPAddress $StaticIP -ErrorAction SilentlyContinue)) {
            New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $StaticIP `
                -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
        }
        # a DC points its DNS at itself
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $StaticIP
    }

    Write-Host "[*] Installing AD DS role..."
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

    Write-Host "[*] Promoting to a new forest '$DomainName' (reboots on completion)..."
    $dsrm = ConvertTo-SecureString $DsrmPassword -AsPlainText -Force
    Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetBIOSName `
        -SafeModeAdministratorPassword $dsrm -InstallDns -Force
    # --- machine reboots here; run this script again afterwards ---
}
else {
    $domain = (Get-ADDomain).DNSRoot
    Write-Host "[*] PHASE 2 - domain '$domain' is up. Creating warden accounts..." -ForegroundColor Cyan
    foreach ($w in $Wardens) {
        $pwPlain = if ($w.Pass) { $w.Pass } else { $UserPassword }
        $pw = ConvertTo-SecureString $pwPlain -AsPlainText -Force
        $exists = Get-ADUser -Filter "SamAccountName -eq '$($w.Sam)'" -ErrorAction SilentlyContinue
        if ($exists) {
            Set-ADAccountPassword -Identity $w.Sam -NewPassword $pw -Reset
            Write-Host "    ~ $($w.Sam) already exists, password reset" -ForegroundColor Yellow
        } else {
            New-ADUser -Name $w.Name -SamAccountName $w.Sam `
                -UserPrincipalName "$($w.Sam)@$domain" -EmailAddress $w.Email `
                -AccountPassword $pw -Enabled $true
            Write-Host "    + created $($w.Sam)@$domain" -ForegroundColor Green
        }
    }

    Write-Host "`n[*] Current users:"
    Get-ADUser -Filter * | Select-Object Name, SamAccountName, UserPrincipalName | Format-Table -AutoSize
    Write-Host "[OK] Domain controller ready. DNSRoot = $domain (use this as AD_DOMAIN in cgi-bin/login.py)." -ForegroundColor Green
}

Stop-Transcript | Out-Null
