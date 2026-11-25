<#
    Remove-Zabbix.ps1 - remove o Zabbix Agent (MSI e instalacoes legadas).

    - Desinstala pelo ProductCode quando o produto esta no registro.
    - Remove servicos remanescentes (Zabbix Agent / Zabbix Agent 2).
    - Faz backup da configuracao antes de remover arquivos.
    - -RemoveFiles apaga tambem os diretorios de instalacao.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\scripts\Remove-Zabbix.ps1
        powershell -ExecutionPolicy Bypass -File .\scripts\Remove-Zabbix.ps1 -RemoveFiles
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$RemoveFiles
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\settings.psd1' }
$config = Get-VtxConfig -Path $ConfigPath
$log = Initialize-VtxLog -Name 'remove-zabbix' -LogDir $config.Common.LogDir

$exitCode = 0

try {
    Assert-Administrator
    Write-Log -Message 'Removendo Zabbix Agent' -Level STEP

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $config.Common.BackupDir "zabbix-removido-$stamp"

    foreach ($conf in @(
        'C:\Program Files\Zabbix Agent\zabbix_agentd.conf',
        'C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf',
        'C:\Zabbix\zabbix_agentd.conf'
    )) {
        if (Test-Path -LiteralPath $conf) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item -LiteralPath $conf -Destination $backupDir -Force
            Write-Log -Message "Backup: $conf -> $backupDir" -Level INFO
        }
    }

    # Desinstalacao via MSI
    $products = Get-InstalledProduct -NamePattern '^Zabbix Agent'
    foreach ($product in $products) {
        if (-not $product.ProductCode) {
            Write-Log -Message "Produto sem ProductCode: $($product.DisplayName)" -Level WARN
            continue
        }

        Write-Log -Message "Desinstalando $($product.DisplayName) $($product.DisplayVersion)" -Level STEP
        $msiLog = Join-Path $config.Common.LogDir ("zabbix_uninstall_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $msiExit = Invoke-MsiProcess -Arguments ('/x {0} /qn /norestart /l*v "{1}"' -f $product.ProductCode, $msiLog)

        if ($msiExit -eq 0 -or $msiExit -eq 3010) {
            Write-Log -Message "Desinstalacao concluida (exit $msiExit)." -Level OK
        }
        else {
            Write-Log -Message "Desinstalacao retornou exit $msiExit. Consulte $msiLog" -Level WARN
            $exitCode = 1
        }
    }

    # Servicos remanescentes (instalacao manual ou MSI incompleto)
    foreach ($name in @('Zabbix Agent', 'Zabbix Agent 2')) {
        if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
            Remove-VtxService -Name $name | Out-Null
            Write-Log -Message "Servico removido: $name" -Level OK
        }
    }

    # Arquivos
    if ($RemoveFiles) {
        foreach ($dir in @('C:\Program Files\Zabbix Agent', 'C:\Program Files\Zabbix Agent 2', 'C:\Zabbix')) {
            if (Test-Path -LiteralPath $dir) {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Message "Diretorio removido: $dir" -Level OK
            }
        }
    }
    else {
        Write-Log -Message 'Diretorios de instalacao mantidos (use -RemoveFiles para apagar).' -Level INFO
    }

    Write-Log -Message 'Remocao do Zabbix Agent concluida.' -Level OK
}
catch {
    Write-Log -Message ("Falha: " + $_.Exception.Message) -Level ERROR
    $exitCode = 1
}

exit $exitCode
