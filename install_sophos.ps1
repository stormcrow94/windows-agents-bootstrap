#Requires -Version 5.1
# Sophos Endpoint silent install. URL from config\settings.psd1

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

$installerPath = Join-Path $env:TEMP 'SophosSetup.exe'

try {
    if (-not (Test-InstallAdministrator)) {
        Write-InstallError 'Run this script as Administrator.'
        exit 1
    }

    Initialize-InstallLogging -Prefix 'sophos'
    Write-InstallHeader 'Sophos Endpoint installation'

    $settings = Import-InstallSettings
    if ($settings.CheckInternet) {
        $to = if ($settings.NetworkTimeoutSeconds) { [int]$settings.NetworkTimeoutSeconds } else { 30 }
        Test-InstallInternet -TimeoutSeconds $to | Out-Null
    }

    $sophosInstallerUrl = $settings.SophosInstallerUrl
    $installArgs = if ($settings.SophosInstallArgs) { $settings.SophosInstallArgs } else { '--quiet' }

    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $isServer = $osInfo.ProductType -ne 1
    $systemType = if ($isServer) { 'Server' } else { 'Workstation' }
    Write-InstallInfo ("Detected OS type: {0}" -f $systemType)

    Write-InstallInfo '[1/2] Downloading Sophos Setup...'
    Invoke-WebRequest -Uri $sophosInstallerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    Write-InstallSuccess 'Download completed.'

    Write-InstallInfo '[2/2] Installing (silent)...'
    $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-InstallSuccess 'Installation completed.'
    } elseif ($process.ExitCode -eq 3010) {
        Write-InstallWarning 'Installation completed; reboot required.'
    } else {
        throw ("Installation failed. Exit code: {0}" -f $process.ExitCode)
    }

    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-InstallSuccess 'Sophos Endpoint installation finished.'
    exit 0
} catch {
    Write-InstallError $_.Exception.Message
    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
