#Requires -Version 5.1
# Wazuh Agent install for Windows. Settings: config\settings.psd1

param(
    [string]$WazuhManager,
    [string]$MsiUrl
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

$installerPath = $null
try {
    if (-not (Test-InstallAdministrator)) {
        Write-InstallError 'Run this script as Administrator.'
        exit 1
    }

    Initialize-InstallLogging -Prefix 'wazuh'
    Write-InstallHeader 'Wazuh Agent installation'

    $settings = Import-InstallSettings
    if ($settings.CheckInternet) {
        $to = if ($settings.NetworkTimeoutSeconds) { [int]$settings.NetworkTimeoutSeconds } else { 30 }
        Test-InstallInternet -TimeoutSeconds $to | Out-Null
    }

    $wazuhInstallerUrl = if ($MsiUrl) { $MsiUrl } else { $settings.WazuhMsiUrl }
    $manager = if ($WazuhManager) { $WazuhManager } else { $settings.WazuhManager }
    $uriObj = $null
    if (-not [System.Uri]::TryCreate($wazuhInstallerUrl, [System.UriKind]::Absolute, [ref]$uriObj)) {
        throw 'Invalid Wazuh MSI URL.'
    }
    $fileName = [System.IO.Path]::GetFileName($uriObj.LocalPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'wazuh-agent.msi'
    }
    $installerPath = Join-Path $env:TEMP $fileName

    Write-InstallInfo '[1/3] Downloading Wazuh Agent MSI...'
    Invoke-WebRequest -Uri $wazuhInstallerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    Write-InstallSuccess 'Download completed.'

    Write-InstallInfo '[2/3] Installing...'
    $installArgs = @('/i', "`"$installerPath`"", '/q', ('WAZUH_MANAGER={0}' -f $manager))
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw ("Installation failed. Exit code: {0}" -f $process.ExitCode)
    }
    Write-InstallSuccess 'Installation completed.'

    Write-InstallInfo '[3/3] Starting Wazuh service...'
    Start-Sleep -Seconds 3
    $startService = Start-Process -FilePath 'net' -ArgumentList 'start', 'Wazuh' -Wait -PassThru -NoNewWindow
    if ($startService.ExitCode -eq 0) {
        Write-InstallSuccess 'Service started.'
    } else {
        Write-InstallWarning 'Could not start service automatically. Try: NET START Wazuh'
    }

    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-InstallSuccess ("Wazuh Agent ready. Manager: {0}" -f $manager)
    exit 0
} catch {
    Write-InstallError $_.Exception.Message
    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
