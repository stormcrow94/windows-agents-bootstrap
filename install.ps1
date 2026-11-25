<#
    install.ps1 - ponto de entrada dos instaladores Vantix para Windows.

    Sem parametros abre o menu interativo. Com flags executa direto:

        .\install.ps1 -Zabbix
        .\install.ps1 -Sophos
        .\install.ps1 -Wazuh
        .\install.ps1 -All
        .\install.ps1 -RemoveZabbix
        .\install.ps1 -All -Force        # reinstala mesmo se ja estiver na versao

    Requer PowerShell 5.1 e execucao como Administrador.
#>
[CmdletBinding()]
param(
    [switch]$Zabbix,
    [switch]$Sophos,
    [switch]$Wazuh,
    [switch]$RemoveZabbix,
    [switch]$All,
    [switch]$Force,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'config\settings.psd1' }

$failures = 0

function Invoke-InstallerScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $path = Join-Path $root ("scripts\{0}" -f $Name)
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Script nao encontrado: $path" -ForegroundColor Red
        $script:failures++
        return
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path, '-ConfigPath', $ConfigPath)
    if ($Force) { $arguments += '-Force' }

    Write-Host ''
    Write-Host ("=== {0} ===" -f $Name) -ForegroundColor Cyan

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        $script:failures++
        Write-Host ("{0} terminou com exit {1}" -f $Name, $proc.ExitCode) -ForegroundColor Red
    }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '=============================================' -ForegroundColor Cyan
        Write-Host ' Instalador Vantix - Windows' -ForegroundColor Cyan
        Write-Host '=============================================' -ForegroundColor Cyan
        Write-Host ' 1) Zabbix Agent'
        Write-Host ' 2) Sophos Endpoint'
        Write-Host ' 3) Wazuh Agent'
        Write-Host ' 4) Remover Zabbix Agent'
        Write-Host ' 5) Instalar tudo (Zabbix + Sophos + Wazuh)'
        Write-Host ' 0) Sair'
        Write-Host ''

        $option = Read-Host 'Opcao'
        switch ($option) {
            '1' { Invoke-InstallerScript -Name 'Install-Zabbix.ps1' }
            '2' { Invoke-InstallerScript -Name 'Install-Sophos.ps1' }
            '3' { Invoke-InstallerScript -Name 'Install-Wazuh.ps1' }
            '4' { Invoke-InstallerScript -Name 'Remove-Zabbix.ps1' }
            '5' {
                Invoke-InstallerScript -Name 'Install-Zabbix.ps1'
                Invoke-InstallerScript -Name 'Install-Sophos.ps1'
                Invoke-InstallerScript -Name 'Install-Wazuh.ps1'
            }
            '0' { return }
            default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow }
        }
    }
}

$hasFlags = $Zabbix -or $Sophos -or $Wazuh -or $RemoveZabbix -or $All

if (-not $hasFlags) {
    Show-Menu
    if ($failures -gt 0) { exit 1 }
    exit 0
}

if ($All) {
    Invoke-InstallerScript -Name 'Install-Zabbix.ps1'
    Invoke-InstallerScript -Name 'Install-Sophos.ps1'
    Invoke-InstallerScript -Name 'Install-Wazuh.ps1'
}
else {
    if ($Zabbix) { Invoke-InstallerScript -Name 'Install-Zabbix.ps1' }
    if ($Sophos) { Invoke-InstallerScript -Name 'Install-Sophos.ps1' }
    if ($Wazuh) { Invoke-InstallerScript -Name 'Install-Wazuh.ps1' }
    if ($RemoveZabbix) { Invoke-InstallerScript -Name 'Remove-Zabbix.ps1' }
}

if ($failures -gt 0) {
    Write-Host ''
    Write-Host ("Concluido com {0} falha(s). Veja os logs em C:\ProgramData\Vantix\install-logs" -f $failures) -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Todas as operacoes concluidas com sucesso.' -ForegroundColor Green
exit 0
