<#
.SYNOPSIS
    Valida la condicion AlwaysInstallElevated.
    Vulnerable solo si AMBAS claves (HKLM y HKCU) estan en 1.
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
            $value = 0   # clave/valor ausente => tratado como deshabilitado
        }
        $results[$hive] = [int]$value
    }

    $vulnerable = ($results['HKLM'] -eq 1) -and ($results['HKCU'] -eq 1)

    [PSCustomObject]@{
        HKLM                = $results['HKLM']
        HKCU                = $results['HKCU']
        Vulnerable          = $vulnerable
        AbuseFunctionPowerUp = if ($vulnerable) { 'Write-UserAddMSI' } else { $null }
    }
}

# Ejecutar
$r = Test-AlwaysInstallElevated
$r | Format-List

if ($r.Vulnerable) {
    Write-Host "[!] VULNERABLE: AlwaysInstallElevated habilitado en ambos hives." -ForegroundColor Red
} else {
    Write-Host "[+] No vulnerable (se requieren HKLM y HKCU = 1)." -ForegroundColor Green
}