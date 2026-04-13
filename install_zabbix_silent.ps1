#Requires -Version 5.1
# Silent Zabbix Agent install for Windows. Settings: config\settings.psd1

param(
    [string]$ZabbixServer,
    [string]$ZabbixServerActive,
    [string]$MsiUrl
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $common

function Test-ZabbixInstalled {
    $zabbixService = Get-Service -Name 'Zabbix*' -ErrorAction SilentlyContinue
    return [bool]$zabbixService
}

function Remove-ZabbixPrevious {
    Write-InstallWarning 'Existing Zabbix installation detected. Removing...'

    $services = Get-Service -Name 'Zabbix*' -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        }
    }

    $packages = Get-Package -Name '*Zabbix*' -ErrorAction SilentlyContinue
    foreach ($package in $packages) {
        try {
            Uninstall-Package -Name $package.Name -Confirm:$false -ErrorAction SilentlyContinue
            Write-InstallSuccess ("Removed package: {0}" -f $package.Name)
        } catch {
            Write-InstallWarning ("Could not remove package {0}: {1}" -f $package.Name, $_)
        }
    }
    Start-Sleep -Seconds 2
}

function Install-ZabbixSilentInternal {
    $settings = Import-InstallSettings

    if ($settings.CheckInternet) {
        $to = if ($settings.NetworkTimeoutSeconds) { [int]$settings.NetworkTimeoutSeconds } else { 30 }
        Test-InstallInternet -TimeoutSeconds $to | Out-Null
    }

    $zabbixAgentUrl = if ($MsiUrl) { $MsiUrl } else { $settings.ZabbixMsiUrl }
    $zabbixServerIp = if ($ZabbixServer) { $ZabbixServer } else { $settings.ZabbixServer }
    $zabbixProxyIp = if ($ZabbixServerActive) { $ZabbixServerActive } else { $settings.ZabbixServerActive }

    $uriObj = $null
    if (-not [System.Uri]::TryCreate($zabbixAgentUrl, [System.UriKind]::Absolute, [ref]$uriObj)) {
        Write-InstallError 'Invalid Zabbix MSI URL.'
        return $false
    }
    $fileName = [System.IO.Path]::GetFileName($uriObj.LocalPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'zabbix_agent.msi'
    }
    $downloadPath = Join-Path $env:TEMP $fileName

    if ($env:COMPUTERNAME) {
        $zabbixHostname = $env:COMPUTERNAME
    } elseif (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue) {
        $zabbixHostname = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
    } else {
        $zabbixHostname = [System.Net.Dns]::GetHostName()
    }

    if ([string]::IsNullOrWhiteSpace($zabbixHostname)) {
        Write-InstallError 'Could not determine computer name. Aborting.'
        return $false
    }

    $configPaths = @(
        'C:\Program Files\Zabbix Agent\zabbix_agentd.conf',
        'C:\Program Files (x86)\Zabbix Agent\zabbix_agentd.conf',
        'C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf',
        'C:\Program Files (x86)\Zabbix Agent 2\zabbix_agent2.conf'
    )

    Write-InstallHeader 'Zabbix Agent (silent)'
    Write-InstallInfo ("Zabbix server: {0}" -f $zabbixServerIp)
    Write-InstallInfo ("ServerActive (proxy): {0}" -f $zabbixProxyIp)
    Write-InstallInfo ("Hostname: {0}" -f $zabbixHostname)

    if (Test-ZabbixInstalled) {
        Remove-ZabbixPrevious
        Start-Sleep -Seconds 3
    }

    Write-InstallInfo '[1/5] Downloading Zabbix Agent MSI...'
    try {
        Invoke-WebRequest -Uri $zabbixAgentUrl -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
        Write-InstallSuccess 'Download completed.'
    } catch {
        Write-InstallError ("Download failed: {0}" -f $_)
        return $false
    }

    Write-InstallInfo '[2/5] Installing (silent)...'
    try {
        $installArgs = @(
            '/i', "`"$downloadPath`"",
            '/qn',
            '/norestart',
            "SERVER=$zabbixServerIp",
            "SERVERACTIVE=$zabbixProxyIp",
            "HOSTNAME=$zabbixHostname"
        )
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-InstallSuccess ('Installation finished (exit code {0}).' -f $process.ExitCode)
        } else {
            Write-InstallWarning ('msiexec exit code: {0}' -f $process.ExitCode)
        }
    } catch {
        Write-InstallError ("Install failed: {0}" -f $_)
        return $false
    }

    Start-Sleep -Seconds 3

    Write-InstallInfo '[3/5] Locating configuration file...'
    $configPath = $null
    foreach ($path in $configPaths) {
        if (Test-Path -LiteralPath $path) {
            $configPath = $path
            break
        }
    }
    if (-not $configPath) {
        foreach ($dirPattern in @('C:\Program Files\Zabbix*', 'C:\Program Files (x86)\Zabbix*')) {
            $dirs = Get-ChildItem -Path $dirPattern -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $dirs) {
                $found = Get-ChildItem -Path (Join-Path $dir.FullName '*agent*.conf') -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $configPath = $found.FullName
                    break
                }
            }
            if ($configPath) { break }
        }
    }

    if ($configPath) {
        Write-InstallInfo '[4/5] Updating configuration...'
        try {
            if ($settings.AutoBackup) {
                $bak = '{0}.backup.{1}' -f $configPath, (Get-Date -Format 'yyyyMMdd_HHmmss')
                Copy-Item -LiteralPath $configPath -Destination $bak -Force
                Write-InstallInfo ("Backup: {0}" -f $bak)
            }
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent = $configContent -replace '(?m)^Server=.*', "Server=$zabbixServerIp"
            $configContent = $configContent -replace '(?m)^ServerActive=.*', "ServerActive=$zabbixProxyIp"
            $configContent = $configContent -replace '(?m)^Hostname=.*', "Hostname=$zabbixHostname"
            $configContent = $configContent -replace '(?m)^#\s*Server=.*', "Server=$zabbixServerIp"
            $configContent = $configContent -replace '(?m)^#\s*ServerActive=.*', "ServerActive=$zabbixProxyIp"
            $configContent = $configContent -replace '(?m)^#\s*Hostname=.*', "Hostname=$zabbixHostname"
            Set-Content -LiteralPath $configPath -Value $configContent -NoNewline
            Write-InstallSuccess 'Configuration updated.'
        } catch {
            Write-InstallWarning ("Could not update config: {0}" -f $_)
        }
    } else {
        Write-InstallWarning 'Configuration file not found; verify paths after install.'
    }

    Write-InstallInfo '[5/5] Starting Zabbix service...'
    Start-Sleep -Seconds 2
    try {
        $zabbixService = Get-Service -Name 'Zabbix*' -ErrorAction Stop
        if ($zabbixService.Status -ne 'Running') {
            Start-Service -Name $zabbixService.Name -ErrorAction Stop
        } else {
            Restart-Service -Name $zabbixService.Name -ErrorAction Stop
        }
        Write-InstallSuccess ('Service {0} is running.' -f $zabbixService.Name)
    } catch {
        Write-InstallWarning ("Could not start service automatically: {0}" -f $_)
    }

    if (Test-Path -LiteralPath $downloadPath) {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
    }

    Write-InstallSuccess 'Zabbix Agent installation completed.'
    return $true
}

try {
    if (-not (Test-InstallAdministrator)) {
        Write-Host 'Administrator rights required. Relaunching elevated...' -ForegroundColor Yellow
        $path = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        Start-Process PowerShell.exe -Verb RunAs -ArgumentList '-NoExit', '-File', "`"$path`""
        exit
    }

    Initialize-InstallLogging -Prefix 'zabbix'
    $ok = Install-ZabbixSilentInternal
    exit ($(if ($ok) { 0 } else { 1 }))
} catch {
    Write-InstallError $_.Exception.Message
    exit 1
}
