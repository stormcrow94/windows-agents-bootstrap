#Requires -Version 5.1
# Main menu: parity with upstream Linux installer.sh (Windows).

$ErrorActionPreference = 'Continue'

function Get-MainScriptDirectory {
    if ($MyInvocation.MyCommand.Path) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if ($PSCommandPath) {
        return Split-Path -Parent $PSCommandPath
    }
    return Split-Path -Parent $MyInvocation.PSCommandPath
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "     APPLICATION INSTALLATION MANAGER (Windows / PowerShell)     " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-SystemInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $name = if ($cs) { $cs.Name } else { $env:COMPUTERNAME }
        $caption = if ($os) { $os.Caption } else { 'Windows' }
        $domain = if ($cs -and $cs.PartOfDomain) { $cs.Domain } else { 'WORKGROUP' }
        Write-Host ("OS: {0}" -f $caption) -ForegroundColor White
        Write-Host ("Computer: {0}  |  Domain: {1}" -f $name, $domain) -ForegroundColor White
        Write-Host ""
    } catch {
        Write-Host ""
    }
}

function Show-Menu {
    Write-Host "MAIN MENU" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [1] Install Zabbix Agent" -ForegroundColor Green
    Write-Host "  [2] Configure computer name (hostname)" -ForegroundColor Green
    Write-Host "  [3] Install Wazuh Agent" -ForegroundColor Green
    Write-Host "  [4] Install Sophos" -ForegroundColor Green
    Write-Host "  [5] Join Active Directory domain" -ForegroundColor Green
    Write-Host "  [6] Full install (hostname, Zabbix, Wazuh, optional Sophos & domain)" -ForegroundColor Cyan
    Write-Host "  [7] Edit settings (config\settings.psd1)" -ForegroundColor Yellow
    Write-Host "  [8] View logs" -ForegroundColor Yellow
    Write-Host "  [9] Remove Zabbix Agent" -ForegroundColor Yellow
    Write-Host "  [0] Exit" -ForegroundColor Red
    Write-Host ""
}

function Invoke-ScriptWithTimeout {
    param(
        [string]$ScriptPath,
        [string]$ScriptName,
        [int]$TimeoutSeconds = 1800
    )

    $result = @{
        Success  = $false
        Message  = ''
        ExitCode = -1
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $result.Message = "Script not found: $ScriptPath"
        return $result
    }

    $scriptContent = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($scriptContent)) {
        $result.Message = 'Script is empty'
        return $result
    }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Executing: $ScriptName" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""

    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"" -PassThru -WindowStyle Normal
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    $process.WaitForExit(5000)
                }
            } catch { }
            $result.Success = $false
            $result.Message = "Script execution timed out after $TimeoutSeconds seconds"
            $result.ExitCode = -2
        } else {
            $exitCode = $process.ExitCode
            $result.ExitCode = $exitCode
            if ($exitCode -eq 0) {
                $result.Success = $true
                $result.Message = 'Completed successfully'
            } else {
                $result.Success = $false
                $result.Message = "Failed with exit code: $exitCode"
            }
        }
    } catch {
        $result.Success = $false
        $result.Message = "Error executing script: $_"
        $result.ExitCode = -1
    }

    return $result
}

function Show-Result {
    param(
        [string]$ScriptName,
        [hashtable]$Result
    )
    Write-Host ""
    if ($Result.Success) {
        Write-Host "SUCCESS: $ScriptName - $($Result.Message)" -ForegroundColor Green
    } else {
        Write-Host "FAILED: $ScriptName - $($Result.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Open-SettingsFile {
    param([string]$ScriptDir)
    $cfg = Join-Path $ScriptDir 'config\settings.psd1'
    if (-not (Test-Path -LiteralPath $cfg)) {
        Write-Host "Settings file not found: $cfg" -ForegroundColor Red
        return
    }
    $notepad = Join-Path $env:WINDIR 'notepad.exe'
    if (Test-Path -LiteralPath $notepad) {
        Start-Process -FilePath $notepad -ArgumentList "`"$cfg`""
        Write-Host "Opened in Notepad. Save and close when done." -ForegroundColor Green
    } else {
        Write-Host "Notepad not found. Edit manually:" -ForegroundColor Yellow
        Write-Host $cfg
    }
}

function Show-LogPicker {
    param([string]$ScriptDir)
    $commonPath = Join-Path $ScriptDir 'lib\Common.ps1'
    if (-not (Test-Path -LiteralPath $commonPath)) {
        Write-Host "Common library not found." -ForegroundColor Red
        return
    }
    . $commonPath
    $logDir = Get-InstallLogDirectory
    if (-not (Test-Path -LiteralPath $logDir)) {
        Write-Host "No logs directory yet: $logDir" -ForegroundColor Yellow
        return
    }
    $logs = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if (-not $logs -or $logs.Count -eq 0) {
        Write-Host 'No log files found.' -ForegroundColor Yellow
        return
    }
    Write-Host 'Available logs:' -ForegroundColor Cyan
    $i = 1
    foreach ($f in $logs) {
        Write-Host ("  [{0}] {1} ({2})" -f $i, $f.Name, $f.LastWriteTime)
        $i++
    }
    Write-Host '  [0] Back' -ForegroundColor Gray
    $choice = Read-Host 'Select log number'
    if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) {
        return
    }
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $logs.Count) {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        return
    }
    $selected = $logs[$idx - 1].FullName
    Write-Host ""
    Write-Host "---- $selected ----" -ForegroundColor Cyan
    Get-Content -LiteralPath $selected -ErrorAction SilentlyContinue | Out-Host
}

function Main {
    if (-not (Test-Administrator)) {
        Write-Host ""
        Write-Host "Administrator rights required. Relaunching elevated..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $MyInvocation.PSCommandPath }
        if (-not $scriptPath) {
            Write-Host 'Could not determine script path.' -ForegroundColor Red
            exit 1
        }
        Start-Process PowerShell.exe -Verb RunAs -ArgumentList '-NoExit', '-File', "`"$scriptPath`""
        exit
    }

    $scriptDir = Get-MainScriptDirectory
    if (-not $scriptDir) {
        Write-Host 'Could not determine script directory.' -ForegroundColor Red
        exit 1
    }

    $commonPath = Join-Path $scriptDir 'lib\Common.ps1'
    if (-not (Test-Path -LiteralPath $commonPath)) {
        Write-Host "Required file missing: $commonPath" -ForegroundColor Red
        exit 1
    }
    . $commonPath
    try {
        Initialize-InstallLogging -Prefix 'installer_menu'
    } catch {
        Write-Host ("Note: logging init failed: {0}" -f $_) -ForegroundColor Yellow
    }

    $scripts = @{
        Zabbix        = Join-Path $scriptDir 'install_zabbix_silent.ps1'
        Hostname      = Join-Path $scriptDir 'hostname.ps1'
        Wazuh         = Join-Path $scriptDir 'install_wazuh.ps1'
        Sophos        = Join-Path $scriptDir 'install_sophos.ps1'
        Domain        = Join-Path $scriptDir 'register_domain.ps1'
        RemoveZabbix  = Join-Path $scriptDir 'remove_zabbix.ps1'
    }

    do {
        Show-Header
        Show-SystemInfo
        Show-Menu
        $choice = Read-Host 'Select an option'

        switch ($choice) {
            '1' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Zabbix -ScriptName 'Install Zabbix Agent' -TimeoutSeconds 1800
                Show-Result -ScriptName 'Install Zabbix Agent' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '2' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Hostname -ScriptName 'Configure computer name' -TimeoutSeconds 600
                Show-Result -ScriptName 'Configure computer name' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '3' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Wazuh -ScriptName 'Install Wazuh' -TimeoutSeconds 1800
                Show-Result -ScriptName 'Install Wazuh' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '4' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Sophos -ScriptName 'Install Sophos' -TimeoutSeconds 1800
                Show-Result -ScriptName 'Install Sophos' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '5' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Domain -ScriptName 'Join Active Directory' -TimeoutSeconds 1800
                Show-Result -ScriptName 'Join Active Directory' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '6' {
                Show-Header
                Write-Host 'Full install runs: computer name (optional), Zabbix, Wazuh, then optional Sophos and domain join.' -ForegroundColor Cyan
                Write-Host ""
                if (-not (Read-InstallConfirm -PromptText 'Continue with full install?' -DefaultYes $false)) {
                    Write-Host 'Cancelled.' -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    continue
                }
                $results = @()

                Write-Host 'Step 1/5: Configure computer name (runs hostname.ps1)...' -ForegroundColor Yellow
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Hostname -ScriptName 'Hostname' -TimeoutSeconds 600
                $results += @{ Name = 'Hostname'; Result = $r }
                Show-Result -ScriptName 'Hostname' -Result $r
                Start-Sleep -Seconds 2

                Write-Host 'Step 2/5: Zabbix Agent...' -ForegroundColor Yellow
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Zabbix -ScriptName 'Zabbix' -TimeoutSeconds 1800
                $results += @{ Name = 'Zabbix'; Result = $r }
                Show-Result -ScriptName 'Zabbix' -Result $r
                Start-Sleep -Seconds 2

                Write-Host 'Step 3/5: Wazuh...' -ForegroundColor Yellow
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Wazuh -ScriptName 'Wazuh' -TimeoutSeconds 1800
                $results += @{ Name = 'Wazuh'; Result = $r }
                Show-Result -ScriptName 'Wazuh' -Result $r
                Start-Sleep -Seconds 2

                Write-Host 'Step 4/5: Sophos (optional)...' -ForegroundColor Yellow
                if (Read-InstallConfirm -PromptText 'Install Sophos now?' -DefaultYes $false) {
                    $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Sophos -ScriptName 'Sophos' -TimeoutSeconds 1800
                    $results += @{ Name = 'Sophos'; Result = $r }
                    Show-Result -ScriptName 'Sophos' -Result $r
                } else {
                    Write-Host 'Sophos skipped.' -ForegroundColor Gray
                }
                Start-Sleep -Seconds 2

                Write-Host 'Step 5/5: Domain join (optional)...' -ForegroundColor Yellow
                if (Read-InstallConfirm -PromptText 'Join Active Directory now?' -DefaultYes $false) {
                    $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.Domain -ScriptName 'Domain' -TimeoutSeconds 1800
                    $results += @{ Name = 'Domain'; Result = $r }
                    Show-Result -ScriptName 'Domain' -Result $r
                } else {
                    Write-Host 'Domain join skipped.' -ForegroundColor Gray
                }

                Write-Host ""
                Write-Host 'SUMMARY' -ForegroundColor Cyan
                foreach ($item in $results) {
                    if ($item.Result.Success) {
                        Write-Host ("  OK   {0}" -f $item.Name) -ForegroundColor Green
                    } else {
                        Write-Host ("  FAIL {0} - {1}" -f $item.Name, $item.Result.Message) -ForegroundColor Red
                    }
                }
                Write-Host ""
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '7' {
                Show-Header
                Open-SettingsFile -ScriptDir $scriptDir
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '8' {
                Show-Header
                Show-LogPicker -ScriptDir $scriptDir
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '9' {
                Show-Header
                $r = Invoke-ScriptWithTimeout -ScriptPath $scripts.RemoveZabbix -ScriptName 'Remove Zabbix' -TimeoutSeconds 600
                Show-Result -ScriptName 'Remove Zabbix' -Result $r
                Write-Host 'Press any key to continue...'
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            '0' {
                Write-Host 'Exiting...' -ForegroundColor Yellow
                exit 0
            }
            default {
                Write-Host 'Invalid option.' -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($true)
}

try {
    Main
} catch {
    Write-Host ("Fatal error: {0}" -f $_) -ForegroundColor Red
    Write-Host 'Press any key to exit...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
