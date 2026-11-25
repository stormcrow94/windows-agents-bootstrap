<#
    Install-Wazuh.ps1 - instala ou repara o Wazuh Agent no Windows.

    Correcao do script antigo: o servico se chama WazuhSvc (nao "Wazuh"),
    o grupo e passado na instalacao e a validacao real (servico + chave +
    log de conexao) substitui o "net start" que falhava sempre.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Wazuh.ps1
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Wazuh.ps1 -Force
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
$w = $config.Wazuh
$log = Initialize-VtxLog -Name 'wazuh' -LogDir $config.Common.LogDir

$exitCode = 0
$serviceName = 'WazuhSvc'
$agentDir = 'C:\Program Files (x86)\ossec-agent'
$confPath = Join-Path $agentDir 'ossec.conf'
$keysPath = Join-Path $agentDir 'client.keys'
$agentLog = Join-Path $agentDir 'ossec.log'

try {
    Assert-Administrator
    Write-Log -Message "Iniciando instalacao do Wazuh Agent $($w.Version)" -Level STEP

    $installed = Get-InstalledProduct -NamePattern '^Wazuh Agent'
    $installedVersion = $null
    if ($installed) { $installedVersion = ($installed | Select-Object -First 1).DisplayVersion }

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if (-not $Force -and (Get-VersionPrefix -Version $installedVersion) -eq (Get-VersionPrefix -Version $w.Version) -and $svc -and $svc.Status -eq 'Running') {
        Write-Log -Message "Wazuh Agent $installedVersion ja instalado e ativo. Nada a fazer." -Level OK
        exit 0
    }

    # ---------------------------------------------------------------
    # Backup da identidade do agente (client.keys) e da configuracao
    # ---------------------------------------------------------------
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $config.Common.BackupDir "wazuh-$stamp"
    $hadKey = $false

    if (Test-Path -LiteralPath $keysPath) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item -LiteralPath $keysPath -Destination $backupDir -Force
        if ((Get-Content -LiteralPath $keysPath | Where-Object { $_ -match '\S' }).Count -gt 0) { $hadKey = $true }
        if (Test-Path -LiteralPath $confPath) { Copy-Item -LiteralPath $confPath -Destination $backupDir -Force }
        Write-Log -Message "Backup do agente em $backupDir (chave existente: $hadKey)" -Level INFO
    }

    # ---------------------------------------------------------------
    # Download do MSI
    # ---------------------------------------------------------------
    $msiName = "wazuh-agent-$($w.Version)-1.msi"
    $msiPath = Join-Path $config.Common.CacheDir $msiName
    $url = "https://packages.wazuh.com/4.x/windows/$msiName"

    if (-not $Force -and (Test-Path -LiteralPath $msiPath) -and (Get-Item -LiteralPath $msiPath).Length -gt 1MB) {
        Write-Log -Message "MSI em cache: $msiPath" -Level INFO
    }
    else {
        Write-Log -Message "Baixando $url" -Level STEP
        $size = Invoke-VtxDownload -Url $url -Destination $msiPath
        Write-Log -Message ("Download concluido ({0:N0} bytes)" -f $size) -Level OK
    }

    # ---------------------------------------------------------------
    # Instalacao
    # ---------------------------------------------------------------
    # Para o servico antes do MSI: o stop durante a reconfiguracao pode
    # estourar o timeout do Windows Installer e deixar o agente parado.
    $svcBefore = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svcBefore -and $svcBefore.Status -ne 'Stopped') {
        Write-Log -Message 'Parando WazuhSvc antes da instalacao...' -Level INFO
        & sc.exe stop $serviceName | Out-Null
        $stateBefore = Wait-VtxServiceSettled -Name $serviceName -TimeoutSec 180
        Write-Log -Message "Estado apos parada: $stateBefore" -Level INFO
    }

    $msiLog = Join-Path $config.Common.LogDir ("wazuh_msi_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    $msiArgs = @(
        "/i `"$msiPath`""
        '/qn'
        '/norestart'
        "/l*v `"$msiLog`""
        "WAZUH_MANAGER=`"$($w.Manager)`""
        "WAZUH_MANAGER_PORT=$($w.ManagerPort)"
        "WAZUH_REGISTRATION_SERVER=`"$($w.RegistrationServer)`""
        "WAZUH_REGISTRATION_PORT=$($w.RegistrationPort)"
        "WAZUH_AGENT_GROUP=`"$($w.AgentGroup)`""
        "WAZUH_AGENT_NAME=`"$env:COMPUTERNAME`""
        "WAZUH_PROTOCOL=`"$($w.Protocol)`""
    ) -join ' '

    Write-Log -Message "Executando msiexec /i $msiName" -Level STEP
    $msiExit = Invoke-MsiProcess -Arguments $msiArgs

    if ($msiExit -eq 3010) {
        Write-Log -Message 'MSI retornou 3010 (reinicio necessario); continuando a validacao.' -Level WARN
    }
    elseif ($msiExit -ne 0) {
        throw "Falha no MSI do Wazuh (exit $msiExit). Consulte $msiLog"
    }

    # ---------------------------------------------------------------
    # Restaura a identidade do agente se o MSI a removeu
    # ---------------------------------------------------------------
    $keyLines = 0
    if (Test-Path -LiteralPath $keysPath) {
        $keyLines = @(Get-Content -LiteralPath $keysPath | Where-Object { $_ -match '\S' }).Count
    }

    if ($keyLines -eq 0 -and $hadKey) {
        Write-Log -Message 'MSI nao preservou client.keys; restaurando do backup.' -Level WARN
        Copy-Item -LiteralPath (Join-Path $backupDir 'client.keys') -Destination $keysPath -Force
        if (Test-Path -LiteralPath (Join-Path $backupDir 'ossec.conf')) {
            Copy-Item -LiteralPath (Join-Path $backupDir 'ossec.conf') -Destination $confPath -Force
        }
        $keyLines = @(Get-Content -LiteralPath $keysPath | Where-Object { $_ -match '\S' }).Count
    }

    # ---------------------------------------------------------------
    # Servico e validacao
    # ---------------------------------------------------------------
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw "Servico $serviceName nao foi criado pelo MSI (nome antigo 'Wazuh' nao existe)."
    }

    $state = Wait-VtxServiceSettled -Name $serviceName -TimeoutSec 240
    if ($state -eq 'Missing') {
        throw "Servico $serviceName desapareceu durante a instalacao."
    }
    if ($state -eq 'Stopped') {
        Write-Log -Message 'Servico ficou parado apos o MSI; iniciando.' -Level INFO
        Start-Service -Name $serviceName
    }
    elseif ($state -ne 'Running') {
        throw "Estado inesperado do servico ${serviceName}: $state"
    }

    if (-not (Wait-VtxServiceStatus -Name $serviceName -Status 'Running' -TimeoutSec 120)) {
        throw "Servico $serviceName nao chegou ao estado Running."
    }
    Write-Log -Message "Servico $serviceName ativo." -Level OK

    # Conexao com o manager: aguarda mensagem no log
    $connected = $false
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $agentLog) {
            $hit = Select-String -LiteralPath $agentLog -Pattern 'Connected to the server|Valid key received|Agent is now online' -ErrorAction SilentlyContinue |
                Select-Object -Last 1
            if ($hit) { $connected = $true; break }
        }
        if (-not (Test-TcpPort -ComputerName $w.Manager -Port ([int]$w.ManagerPort) -TimeoutMs 5000)) {
            Write-Log -Message "Sem conectividade TCP com $($w.Manager):$($w.ManagerPort)" -Level WARN
        }
        Start-Sleep -Seconds 5
    }

    $keyLines = 0
    if (Test-Path -LiteralPath $keysPath) {
        $keyLines = @(Get-Content -LiteralPath $keysPath | Where-Object { $_ -match '\S' }).Count
    }

    Write-Log -Message "Manager: $($w.Manager):$($w.ManagerPort) | Grupo: $($w.AgentGroup)" -Level INFO
    Write-Log -Message "client.keys: $keyLines entrada(s)" -Level INFO

    if ($keyLines -eq 0) {
        throw "Agente sem chave registrada em client.keys. Verifique authd ($($w.RegistrationServer):$($w.RegistrationPort)) e o log $agentLog"
    }

    if (-not $connected) {
        Write-Log -Message "Servico ativo e com chave, mas o log ainda nao mostra conexao com o manager. Verifique $agentLog" -Level WARN
    }
    else {
        Write-Log -Message 'Agente conectado ao manager.' -Level OK
    }

    Write-Log -Message 'Wazuh Agent instalado e validado com sucesso.' -Level OK
}
catch {
    Write-Log -Message ("Falha: " + $_.Exception.Message) -Level ERROR
    $exitCode = 1
}

exit $exitCode
