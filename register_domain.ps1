#Requires -Version 5.1
# Join Active Directory (workgroup machine -> domain). Requires DNS, AD connectivity, and rights to create/reset the computer account.

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

try {
    Initialize-InstallLogging -Prefix 'register_domain'
    Write-InstallHeader 'Join Active Directory domain'

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
    if ($cs.PartOfDomain) {
        Write-InstallError 'This computer is already joined to a domain. Leave the domain first or use domain tools to move/rename the account.'
        exit 1
    }

    $defaultDomain = $settings.DefaultDomain
    $defaultOu = $settings.DefaultDomainOuPath

    if ($defaultDomain) {
        $domain = Read-Host ("DNS domain name [{0}]" -f $defaultDomain)
        if ([string]::IsNullOrWhiteSpace($domain)) { $domain = $defaultDomain }
    } else {
        $domain = Read-Host 'DNS domain name (e.g. corp.example.com)'
    }
    if ([string]::IsNullOrWhiteSpace($domain)) {
        Write-InstallError 'Domain name is required.'
        exit 1
    }

    if ($defaultOu) {
        $ou = Read-Host ("Organizational Unit (LDAP path, optional) [{0}]" -f $defaultOu)
        if ([string]::IsNullOrWhiteSpace($ou)) { $ou = $defaultOu }
    } else {
        $ou = Read-Host 'Organizational Unit (LDAP path, optional; press Enter to skip)'
    }
    if ([string]::IsNullOrWhiteSpace($ou)) { $ou = $null }

    Write-InstallInfo 'Enter credentials for an account that may join this computer to the domain (e.g. domain admin or delegated join account).'
    $cred = Get-Credential -Message "Domain join: $domain"

    Write-InstallInfo "Joining domain '$domain'..."
    $params = @{
        DomainName = $domain
        Credential = $cred
    }
    if ($ou) {
        $params['OUPath'] = $ou
    }

    Add-Computer @params -Force -ErrorAction Stop

    Write-InstallSuccess 'Domain join succeeded. Restart the computer to complete the operation.'
    Write-InstallInfo 'Verify after reboot: System Properties, or run: systeminfo | findstr /B /C:"Domain"'
    exit 0
} catch {
    Write-InstallError $_.Exception.Message
    Write-InstallInfo 'Common causes: DNS cannot resolve the domain, blocked ports (88, 389/636, 445, RPC), duplicate computer name in AD, or insufficient rights.'
    exit 1
}
