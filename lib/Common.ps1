#Requires -Version 5.1

# Shared helpers: repository root, settings, logging, prompts, internet check.

$script:_InstallRepoRoot = $null
$script:_InstallSettings = $null
$script:_InstallLogFile = $null

function Get-InstallRepositoryRoot {
    if ($script:_InstallRepoRoot) {
        return $script:_InstallRepoRoot
    }
    # This file lives in repo\lib
    $script:_InstallRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    return $script:_InstallRepoRoot
}

function Import-InstallSettings {
    if ($null -ne $script:_InstallSettings) {
        return $script:_InstallSettings
    }
    $path = Join-Path (Get-InstallRepositoryRoot) 'config\settings.psd1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Settings file not found: $path"
    }
    $script:_InstallSettings = Import-PowerShellDataFile -LiteralPath $path
    return $script:_InstallSettings
}

function Initialize-InstallLogging {
    param([string]$Prefix = 'installer')

    $settings = Import-InstallSettings
    $root = Get-InstallRepositoryRoot
    $dirName = if ($settings.LogDirName) { $settings.LogDirName } else { 'logs' }
    $logDir = Join-Path $root $dirName
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:_InstallLogFile = Join-Path $logDir ("{0}_{1}.log" -f $Prefix, $stamp)
    Write-InstallLogLine 'INFO' ("Logging started at {0}" -f (Get-Date -Format 'o'))
}

function Write-InstallLogLine {
    param(
        [string]$Level,
        [string]$Message
    )
    if (-not $script:_InstallLogFile) { return }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:_InstallLogFile -Value $line -Encoding UTF8
}

function Write-InstallInfo {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
    Write-InstallLogLine 'INFO' $Message
}

function Write-InstallSuccess {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
    Write-InstallLogLine 'SUCCESS' $Message
}

function Write-InstallWarning {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
    Write-InstallLogLine 'WARNING' $Message
}

function Write-InstallError {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    Write-InstallLogLine 'ERROR' $Message
}

function Write-InstallHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================" -ForegroundColor Magenta
    Write-Host " $Title" -ForegroundColor Magenta
    Write-Host "================================" -ForegroundColor Magenta
    Write-Host ""
    Write-InstallLogLine 'INFO' $Title
}

function Test-InstallAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InstallInternet {
    param([int]$TimeoutSeconds = 30)

    Write-InstallInfo 'Checking internet connectivity...'
    try {
        $ping = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction Stop
        if ($ping) {
            Write-InstallSuccess 'Internet check: OK'
            return $true
        }
    } catch {
        # ICMP may be blocked
    }
    Write-InstallWarning 'Internet check inconclusive (ICMP may be blocked). Continuing.'
    return $false
}

function Read-InstallConfirm {
    param(
        [string]$PromptText,
        [bool]$DefaultYes = $false
    )
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $r = Read-Host ("{0} {1}" -f $PromptText, $suffix)
    if ([string]::IsNullOrWhiteSpace($r)) {
        return $DefaultYes
    }
    return $r -match '^(y|yes|s|sim)$'
}

function Test-InstallHostnameFormat {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
}

function Get-InstallLogDirectory {
    $settings = Import-InstallSettings
    $name = if ($settings.LogDirName) { $settings.LogDirName } else { 'logs' }
    return Join-Path (Get-InstallRepositoryRoot) $name
}

function Stop-InstallLogging {
    if ($script:_InstallLogFile) {
        Write-InstallLogLine 'INFO' ("Logging ended at {0}" -f (Get-Date -Format 'o'))
    }
}
