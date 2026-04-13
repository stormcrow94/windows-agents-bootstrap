#Requires -Version 5.1
# Remove Zabbix Agent packages, services, and related registry keys.

$ErrorActionPreference = 'Continue'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

try {
    if (-not (Test-InstallAdministrator)) {
        Write-Host 'Administrator rights recommended for full removal.' -ForegroundColor Yellow
    }

    Initialize-InstallLogging -Prefix 'remove_zabbix'
    Write-InstallHeader 'Remove Zabbix Agent'

    $searchString = 'Zabbix'
    Write-InstallInfo 'Detecting Zabbix packages...'
    Start-Sleep -Seconds 1

    try {
        $packages = Get-Package -Name "*$searchString*" -ErrorAction SilentlyContinue
    } catch {
        $packages = @()
    }

    if ($null -eq $packages -or $packages.Count -eq 0) {
        Write-InstallInfo 'No Zabbix packages found via Get-Package.'
    } else {
        $packages | Format-Table -AutoSize
        foreach ($package in $packages) {
            try {
                Uninstall-Package -Name $package.Name -Confirm:$false -ErrorAction Stop
                Write-InstallSuccess ("Uninstalled: {0}" -f $package.Name)
            } catch {
                Write-InstallWarning ("Uninstall failed for {0}: {1}" -f $package.Name, $_)
            }
            $installPath = $package.InstallLocation
            if ($installPath -and (Test-Path -LiteralPath $installPath)) {
                try {
                    Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction Stop
                    Write-InstallInfo ("Removed directory: {0}" -f $installPath)
                } catch {
                    Write-InstallWarning ("Could not remove directory {0}: {1}" -f $installPath, $_)
                }
            }
            Start-Sleep -Seconds 1
        }
    }

    Write-InstallInfo 'Removing Zabbix-related registry keys (if present)...'
    Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Zabbix Agent 2' -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\System\Zabbix Agent' -Recurse -ErrorAction SilentlyContinue

    Write-InstallInfo 'Removing Zabbix services...'
    $null = & sc.exe delete 'Zabbix Agent 2' 2>&1
    Start-Sleep -Seconds 1
    $null = & sc.exe delete 'Zabbix Agent' 2>&1

    Write-InstallSuccess 'Zabbix removal steps completed.'
    exit 0
} catch {
    Write-InstallError $_.Exception.Message
    exit 1
}
