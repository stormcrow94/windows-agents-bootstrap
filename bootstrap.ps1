<#
    bootstrap.ps1 - baixa este repositorio e executa o instalador de agentes.

    Uso em uma linha (PowerShell como usuario comum; pede elevacao sozinho):

        iwr https://raw.githubusercontent.com/stormcrow94/windows-agents-bootstrap/main/bootstrap.ps1 -OutFile "$env:TEMP\bootstrap.ps1"; & "$env:TEMP\bootstrap.ps1" -Component All

    Componentes: Menu (padrao), All, Zabbix, Wazuh, Sophos, RemoveZabbix.

    Opcoes:
        -Component <nome>   componente a executar (padrao: Menu)
        -Force              reinstala mesmo se ja estiver na versao
        -Repo <owner/repo>  repositorio alternativo
        -Branch <nome>      branch alternativo (padrao: main)
        -InstallDir <path>  destino (padrao: C:\ProgramData\AgentsBootstrap)
        -KeepSettings       preserva config\settings.psd1 existente
        -DownloadOnly       baixa e prepara os arquivos sem instalar
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'All', 'Zabbix', 'Wazuh', 'Sophos', 'RemoveZabbix')]
    [string]$Component = 'Menu',
    [switch]$Force,
    [string]$Repo = 'stormcrow94/windows-agents-bootstrap',
    [string]$Branch = 'main',
    [string]$InstallDir = (Join-Path $env:ProgramData 'AgentsBootstrap'),
    [switch]$KeepSettings,
    [switch]$DownloadOnly
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Reexecuta elevado (UAC) quando necessario. -DownloadOnly nao exige administrador.
if (-not $DownloadOnly -and -not (Test-Elevated)) {
    if (-not $PSCommandPath) {
        Write-Host 'Execute em uma janela do PowerShell como Administrador.' -ForegroundColor Yellow
        exit 1
    }

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
        '-Component', $Component
        '-Repo', $Repo
        '-Branch', $Branch
        '-InstallDir', ('"{0}"' -f $InstallDir)
    )
    if ($Force) { $arguments += '-Force' }
    if ($KeepSettings) { $arguments += '-KeepSettings' }

    Write-Host 'Solicitando elevacao (UAC)...' -ForegroundColor Cyan
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $proc.ExitCode
}

$workRoot = Join-Path $env:TEMP ('wab-{0}' -f ([guid]::NewGuid().ToString('N')))
$zipPath = Join-Path $workRoot 'repo.zip'
$extractPath = Join-Path $workRoot 'extract'

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    $url = 'https://codeload.github.com/{0}/zip/refs/heads/{1}' -f $Repo, $Branch
    Write-Host ("Baixando {0} ({1})..." -f $Repo, $Branch) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    $source = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    if (-not $source) { throw 'Pacote baixado sem diretorio raiz.' }

    $settingsPath = Join-Path $InstallDir 'config\settings.psd1'
    $preservedSettings = $null
    if ($KeepSettings -and (Test-Path -LiteralPath $settingsPath)) {
        $preservedSettings = Get-Content -LiteralPath $settingsPath -Raw
        Write-Host 'settings.psd1 existente sera preservado.' -ForegroundColor Yellow
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $source.FullName '*') -Destination $InstallDir -Recurse -Force

    if ($preservedSettings) {
        Set-Content -LiteralPath $settingsPath -Value $preservedSettings -Encoding UTF8
    }

    Write-Host ("Arquivos prontos em {0}" -f $InstallDir) -ForegroundColor Green

    if ($DownloadOnly) {
        Write-Host 'Download concluido (-DownloadOnly); nada foi instalado.' -ForegroundColor Green
        exit 0
    }

    $installer = Join-Path $InstallDir 'install.ps1'
    if (-not (Test-Path -LiteralPath $installer)) { throw "install.ps1 nao encontrado em $InstallDir" }

    $params = @{}
    switch ($Component) {
        'All' { $params['All'] = $true }
        'Zabbix' { $params['Zabbix'] = $true }
        'Wazuh' { $params['Wazuh'] = $true }
        'Sophos' { $params['Sophos'] = $true }
        'RemoveZabbix' { $params['RemoveZabbix'] = $true }
    }
    if ($Force) { $params['Force'] = $true }

    & $installer @params
    exit $LASTEXITCODE
}
catch {
    Write-Host ("Falha: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
