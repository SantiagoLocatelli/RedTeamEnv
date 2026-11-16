<#
.SYNOPSIS
    Validates the AlwaysInstallElevated condition.
    Vulnerable only if BOTH keys (HKLM and HKCU) are set to 1.
#>

function Test-AlwaysInstallElevated {
    [CmdletBinding()]
    param()

    $path = 'SOFTWARE\Policies\Microsoft\Windows\Installer'
    $results = @{}

    foreach ($hive in 'HKLM', 'HKCU') {
        try {
            $value = (Get-ItemProperty -Path "${hive}:\$path" `
                -Name 'AlwaysInstallElevated' -ErrorAction Stop).AlwaysInstallElevated
        }
        catch {
            $value = 0   # missing key/value => treated as disabled
        }
        $results[$hive] = [int]$value
    }

    $vulnerable = ($results['HKLM'] -eq 1) -and ($results['HKCU'] -eq 1)

    [PSCustomObject]@{
        HKLM                 = $results['HKLM']
        HKCU                 = $results['HKCU']
        Vulnerable           = $vulnerable
        AbuseFunctionPowerUp = if ($vulnerable) { 'Write-UserAddMSI' } else { $null }
    }
}

# Run
$r = Test-AlwaysInstallElevated
$r | Format-List

if ($r.Vulnerable) {
    Write-Host "[!] VULNERABLE: AlwaysInstallElevated enabled on both hives." -ForegroundColor Red
} else {
    Write-Host "[+] Not vulnerable (requires HKLM and HKCU = 1)." -ForegroundColor Green
}