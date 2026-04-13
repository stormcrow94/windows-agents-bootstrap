#Requires -Version 5.1
# Configure computer name (Windows equivalent of hostname.sh).

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

try {
    Initialize-InstallLogging -Prefix 'hostname'
    Write-InstallHeader 'Computer name configuration'

    if (-not (Test-InstallAdministrator)) {
        Write-InstallError 'This script must be run as Administrator.'
        exit 1
    }

    $settings = Import-InstallSettings
    if ($settings.CheckInternet) {
        $to = if ($settings.NetworkTimeoutSeconds) { [int]$settings.NetworkTimeoutSeconds } else { 30 }
        Test-InstallInternet -TimeoutSeconds $to | Out-Null
    }

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $current = $env:COMPUTERNAME
    Write-InstallInfo ("Current computer name: {0}" -f $current)
    if ($cs.PartOfDomain) {
        Write-InstallWarning 'This computer is joined to a domain. Renaming may require domain permissions or may be restricted.'
        Write-InstallWarning 'NetBIOS names are limited to 15 characters for legacy compatibility.'
    }

    $newName = Read-Host 'Enter new computer name'
    if (-not (Test-InstallHostnameFormat -Name $newName)) {
        Write-InstallError 'Invalid name. Use letters, numbers, and hyphens; start and end with a letter or number (DNS label rules).'
        exit 1
    }

    if ($newName.Length -gt 15) {
        Write-InstallWarning 'Name is longer than 15 characters; some legacy tools may truncate the NetBIOS name.'
    }

    if (-not (Read-InstallConfirm -PromptText ("Rename computer from '{0}' to '{1}'?" -f $current, $newName))) {
        Write-InstallInfo 'Cancelled.'
        exit 0
    }

    Rename-Computer -NewName $newName -Force
    Write-InstallSuccess 'Computer rename scheduled. Restart the system for the change to take effect.'
    exit 0
} catch {
    Write-InstallError $_.Exception.Message
    exit 1
}
