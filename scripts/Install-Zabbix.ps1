<#
    Install-Zabbix.ps1 - instala ou atualiza o Zabbix Agent no Windows.

    - Resolve o ultimo patch do branch configurado no CDN oficial.
    - Preserva Server/ServerActive de uma instalacao existente.
    - Migra instalacoes antigas fora do MSI (ex.: C:\Zabbix) com backup da config.
    - Valida servico, porta e log antes de reportar sucesso.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Zabbix.ps1
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Zabbix.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\settings.psd1' }
$config = Get-VtxConfig -Path $ConfigPath
$z = $config.Zabbix
$log = Initialize-VtxLog -Name 'zabbix' -LogDir $config.Common.LogDir

$exitCode = 0
$serviceName = 'Zabbix Agent'
$expectedDir = 'C:\Program Files\Zabbix Agent'
$expectedExe = Join-Path $expectedDir 'zabbix_agentd.exe'
$expectedConf = Join-Path $expectedDir 'zabbix_agentd.conf'

try {
    Assert-Administrator
    Write-Log -Message "Iniciando instalacao do Zabbix Agent (branch $($z.Branch))" -Level STEP

    # ---------------------------------------------------------------
    # 1. Configuracao existente: preserva Server/ServerActive
    # ---------------------------------------------------------------
    $server = $z.Server
    $serverActive = $z.ServerActive
    $existingConf = $null

    $confCandidates = @(
        $expectedConf,
        'C:\Zabbix\zabbix_agentd.conf',
        'C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf'
    )

    foreach ($candidate in $confCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $existingConf = $candidate
            break
        }
    }

    if ($existingConf) {
        Write-Log -Message "Configuracao existente encontrada: $existingConf" -Level INFO
        if ($z.PreserveExistingServer) {
            $existingServer = Get-ConfValue -Path $existingConf -Key 'Server'
            $existingServerActive = Get-ConfValue -Path $existingConf -Key 'ServerActive'
            if ($existingServer) {
                $server = $existingServer
                Write-Log -Message "Server preservado da configuracao atual: $server" -Level INFO
            }
            if ($existingServerActive) {
                $serverActive = $existingServerActive
                Write-Log -Message "ServerActive preservado da configuracao atual: $serverActive" -Level INFO
            }
        }
    }

    # ---------------------------------------------------------------
    # 2. Versao alvo
    # ---------------------------------------------------------------
    $url = Get-ZabbixAgentUrl -Branch $z.Branch -Version $z.AgentVersion -StaticUrl $z.StaticUrl
    $targetVersion = [regex]::Match($url, 'zabbix_agent-([\d\.]+)-windows').Groups[1].Value
    if (-not $targetVersion) {
        throw "Nao foi possivel determinar a versao a partir da URL: $url"
    }
    Write-Log -Message "Versao alvo: $targetVersion" -Level INFO

    # ---------------------------------------------------------------
    # 3. Estado atual: MSI e instalacao legada
    # ---------------------------------------------------------------
    $installed = Get-InstalledProduct -NamePattern '^Zabbix Agent'
    $installedVersion = $null
    if ($installed) {
        $installedVersion = ($installed | Select-Object -First 1).DisplayVersion
    }

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $imagePath = Get-ServiceImagePath -Name $serviceName
    $isLegacy = $false

    if ($svc -and $imagePath -and $imagePath -notmatch [regex]::Escape($expectedExe)) {
        $isLegacy = $true
        Write-Log -Message "Instalacao fora do MSI detectada (servico aponta para: $imagePath)" -Level WARN
    }

    if (-not $Force -and (Get-VersionPrefix -Version $installedVersion) -eq (Get-VersionPrefix -Version $targetVersion) -and $svc -and $svc.Status -eq 'Running' -and (Test-Path -LiteralPath $expectedConf)) {
        Write-Log -Message "Zabbix Agent $targetVersion ja instalado e ativo. Nada a fazer." -Level OK
        exit 0
    }

    # ---------------------------------------------------------------
    # 4. Backup e remocao da instalacao legada
    # ---------------------------------------------------------------
    if ($isLegacy) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $config.Common.BackupDir "zabbix-legacy-$stamp"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        foreach ($file in @('C:\Zabbix\zabbix_agentd.conf', 'C:\Zabbix\zabbix_agentd.log')) {
            if (Test-Path -LiteralPath $file) {
                Copy-Item -LiteralPath $file -Destination $backupDir -Force
            }
        }
        Write-Log -Message "Backup da instalacao legada em $backupDir" -Level INFO

        Remove-VtxService -Name $serviceName | Out-Null
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline -and (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 2
        }
        if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
            throw "O servico $serviceName continua registrado apos a remocao. Reinicie o host e execute novamente."
        }
        Write-Log -Message "Servico legado removido." -Level OK
    }

    # ---------------------------------------------------------------
    # 5. Download do MSI
    # ---------------------------------------------------------------
    $msiName = "zabbix_agent-$targetVersion-windows-amd64-openssl.msi"
    $msiPath = Join-Path $config.Common.CacheDir $msiName

    if (-not $Force -and (Test-Path -LiteralPath $msiPath) -and (Get-Item -LiteralPath $msiPath).Length -gt 1MB) {
        Write-Log -Message "MSI em cache: $msiPath" -Level INFO
    }
    else {
        Write-Log -Message "Baixando $url" -Level STEP
        $size = Invoke-VtxDownload -Url $url -Destination $msiPath
        Write-Log -Message ("Download concluido ({0:N0} bytes)" -f $size) -Level OK
    }

    # ---------------------------------------------------------------
    # 6. Instalacao via MSI
    # ---------------------------------------------------------------
    $msiLog = Join-Path $config.Common.LogDir ("zabbix_msi_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    $msiArgs = @(
        "/i `"$msiPath`""
        '/qn'
        '/norestart'
        "/l*v `"$msiLog`""
        "SERVER=`"$server`""
        "SERVERACTIVE=`"$serverActive`""
        "HOSTNAME=`"$env:COMPUTERNAME`""
        "HOSTMETADATA=`"$($z.HostMetadata)`""
        "LISTENPORT=$($z.ListenPort)"
        "STARTAGENTS=$($z.StartAgents)"
        "TIMEOUT=$($z.Timeout)"
        "DEBUGLEVEL=$($z.DebugLevel)"
    ) -join ' '

    Write-Log -Message "Executando msiexec /i $msiName" -Level STEP
    $msiExit = Invoke-MsiProcess -Arguments $msiArgs

    if ($msiExit -eq 3010) {
        Write-Log -Message 'MSI retornou 3010 (reinicio necessario); continuando a validacao.' -Level WARN
    }
    elseif ($msiExit -ne 0) {
        throw "Falha no MSI do Zabbix (exit $msiExit). Consulte $msiLog"
    }

    # ---------------------------------------------------------------
    # 7. Configuracao final e servico
    # ---------------------------------------------------------------
    if (-not (Test-Path -LiteralPath $expectedConf)) {
        throw "Configuracao nao encontrada apos a instalacao: $expectedConf"
    }

    Set-ConfValue -Path $expectedConf -Key 'Server' -Value $server
    Set-ConfValue -Path $expectedConf -Key 'ServerActive' -Value $serverActive
    Set-ConfValue -Path $expectedConf -Key 'Hostname' -Value $env:COMPUTERNAME
    Set-ConfValue -Path $expectedConf -Key 'HostMetadata' -Value $z.HostMetadata
    Set-ConfValue -Path $expectedConf -Key 'ListenPort' -Value ([string]$z.ListenPort)
    Set-ConfValue -Path $expectedConf -Key 'StartAgents' -Value ([string]$z.StartAgents)
    Set-ConfValue -Path $expectedConf -Key 'Timeout' -Value ([string]$z.Timeout)
    Set-ConfValue -Path $expectedConf -Key 'DebugLevel' -Value ([string]$z.DebugLevel)
    Set-ConfValue -Path $expectedConf -Key 'LogFile' -Value (Join-Path $expectedDir 'zabbix_agentd.log')

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw "Servico $serviceName nao foi criado pelo MSI."
    }

    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        $state = Wait-VtxServiceSettled -Name $serviceName -TimeoutSec 120
        if ($state -notin @('Stopped', 'Missing')) {
            Write-Log -Message "Aviso: servico em estado $state apos a parada." -Level WARN
        }
    }

    Start-Service -Name $serviceName

    if (-not (Wait-VtxServiceStatus -Name $serviceName -Status 'Running' -TimeoutSec 90)) {
        throw "Servico $serviceName nao chegou ao estado Running."
    }

    if (-not (Test-TcpPort -ComputerName '127.0.0.1' -Port ([int]$z.ListenPort) -TimeoutMs 5000)) {
        throw "Servico ativo, mas a porta $($z.ListenPort) nao esta ouvindo."
    }

    $agentLog = Join-Path $expectedDir 'zabbix_agentd.log'
    Start-Sleep -Seconds 3
    $logOk = $false
    if (Test-Path -LiteralPath $agentLog) {
        $logOk = [bool](Select-String -LiteralPath $agentLog -Pattern 'Starting Zabbix Agent' -ErrorAction SilentlyContinue | Select-Object -Last 1)
    }

    $binVersion = (Get-Item -LiteralPath $expectedExe).VersionInfo.FileVersion

    Write-Log -Message "Servico: $($svc.Name) = $(($(Get-Service -Name $serviceName)).Status)" -Level OK
    Write-Log -Message "Binario: $binVersion" -Level OK
    Write-Log -Message "Server=$server ServerActive=$serverActive Hostname=$env:COMPUTERNAME" -Level OK
    if (-not $logOk) {
        Write-Log -Message "Aviso: nao encontrei 'Starting Zabbix Agent' em $agentLog" -Level WARN
    }

    Write-Log -Message 'Zabbix Agent instalado e validado com sucesso.' -Level OK
}
catch {
    Write-Log -Message ("Falha: " + $_.Exception.Message) -Level ERROR
    $exitCode = 1
}

exit $exitCode
