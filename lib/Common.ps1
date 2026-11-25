<#
    Common.ps1 - funcoes compartilhadas pelos instaladores de agentes para Windows.

    Compativel com Windows PowerShell 5.1 (padrao do Windows Server 2016+).
    Nao usa recursos de PowerShell 7 (ternario, ??, -Parallel).
#>

$script:VtxLogFile = $null

function Initialize-VtxLog {
    <#
        Cria o arquivo de log da execucao e devolve o caminho.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$LogDir = 'C:\ProgramData\AgentsBootstrap\install-logs'
    )

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:VtxLogFile = Join-Path $LogDir ("{0}_{1}.log" -f $Name, $stamp)
    Set-Content -LiteralPath $script:VtxLogFile -Value ("[{0}] [{1}] inicio {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), 'INFO', $Name) -Encoding UTF8

    return $script:VtxLogFile
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO',
        [string]$LogFile
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"

    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }

    $target = $LogFile
    if (-not $target) { $target = $script:VtxLogFile }
    if ($target) {
        Add-Content -LiteralPath $target -Value $line -Encoding UTF8
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Este script precisa ser executado como Administrador.'
    }
}

function Get-VtxConfig {
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\config\settings.psd1')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de configuracao nao encontrado: $Path"
    }

    return Import-PowerShellDataFile -LiteralPath $Path
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 3000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Invoke-VtxDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 3
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 900
            $size = (Get-Item -LiteralPath $Destination).Length
            if ($size -eq 0) { throw 'arquivo baixado com 0 byte' }
            return $size
        }
        catch {
            if (attempt -eq $Retries) { throw }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Get-InstalledProduct {
    <#
        Le os produtos instalados no registro. Devolve DisplayName, DisplayVersion,
        ProductCode (quando o filho e um GUID) e UninstallString.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$NamePattern
    )

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -match $NamePattern } |
        ForEach-Object {
            $code = $null
            if ($_.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $_.PSChildName }
            [pscustomobject]@{
                DisplayName    = $_.DisplayName
                DisplayVersion = $_.DisplayVersion
                ProductCode    = $code
                UninstallString = $_.UninstallString
            }
        }
}

function Get-ServiceImagePath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $key)) { return $null }
    return (Get-ItemProperty -LiteralPath $key).ImagePath
}

function Stop-VtxService {
    param([Parameter(Mandatory = $true)][string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }
}

function Remove-VtxService {
    <#
        Remove o servico (sc.exe delete). Nao falha se ele nao existir.
        Atencao: o servico fica marcado para remocao ate o proximo boot.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }

    Stop-VtxService -Name $Name
    $output = & sc.exe delete $Name 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Wait-VtxServiceStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status = 'Running',
        [int]$TimeoutSec = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status.ToString() -eq $Status) { return $true }
        Start-Sleep -Seconds 2
    }

    return $false
}

function Wait-VtxServiceSettled {
    <#
        Aguarda o servico sair de estados transitorios (StartPending/StopPending)
        e devolve o estado final: Running, Stopped ou Missing.
        Evita o erro "cannot be stopped" ao reiniciar servicos lentos (ex.: WazuhSvc).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSec = 180
    )

    $transient = @('StartPending', 'StopPending', 'ContinuePending', 'PausePending')
    $deadline = (Get-Date).AddSeconds($TimeoutSec)

    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if (-not $svc) { return 'Missing' }
        if ($transient -notcontains $svc.Status.ToString()) { return $svc.Status.ToString() }
        Start-Sleep -Seconds 2
    }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return 'Missing' }
    return $svc.Status.ToString()
}

function Invoke-MsiProcess {
    <#
        Executa msiexec e devolve o exit code real.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Arguments,
        [int]$TimeoutSec = 1800
    )

    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

function Get-ConfValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $match = Select-String -LiteralPath $Path -Pattern ("^\s*" + [regex]::Escape($Key) + "\s*=\s*(.+?)\s*$") -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value }
    return $null
}

function Set-ConfValue {
    <#
        Substitui (ou acrescenta) uma diretiva chave=valor em arquivo conf.
        Preserva todas as outras linhas e comentarios.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de configuracao nao encontrado: $Path"
    }

    $lines = @(Get-Content -LiteralPath $Path)
    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*="
    $found = $false
    $result = foreach ($line in $lines) {
        if (-not $found -and $line -match $pattern) {
            $found = $true
            "$Key=$Value"
        }
        else {
            $line
        }
    }

    if (-not $found) {
        $result = @($result) + "$Key=$Value"
    }

    Set-Content -LiteralPath $Path -Value $result -Encoding ASCII
}

function Get-VersionPrefix {
    <#
        Normaliza versoes com sufixo de build: '7.0.32.2400' -> '7.0.32'.
        Usado para comparar a versao do MSI com a do registro.
    #>
    param(
        [string]$Version,
        [int]$Parts = 3
    )

    if (-not $Version) { return '' }

    $numbers = @($Version -split '[^0-9]+' | Where-Object { $_ -ne '' })
    if ($numbers.Count -lt $Parts) { return $Version }

    return (($numbers[0..($Parts - 1)]) -join '.')
}

function Get-ZabbixAgentUrl {
    <#
        Resolve a URL do MSI do Zabbix Agent no CDN oficial.
        - Versao 'latest' consulta o diretorio do branch e pega o maior patch.
        - URL fixa pode ser informada em StaticUrl (override total).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Branch,
        [string]$Version = 'latest',
        [string]$StaticUrl = ''
    )

    if ($StaticUrl) { return $StaticUrl }

    $base = "https://cdn.zabbix.com/zabbix/binaries/stable/$Branch/"

    if (-not $Version -or $Version -eq 'latest') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $html = (Invoke-WebRequest -Uri $base -UseBasicParsing -TimeoutSec 120).Content
        $candidates = [regex]::Matches($html, [regex]::Escape($Branch) + '\.(\d+)/') |
            ForEach-Object { "$Branch." + $_.Groups[1].Value } |
            Sort-Object -Unique
        if (-not $candidates) {
            throw "Nao foi possivel identificar a ultima versao $Branch em $base. Informe Zabbix.AgentVersion no settings.psd1."
        }

        $sorted = $candidates | Sort-Object { [int](($_ -split '\.')[2]) }
        $Version = $sorted | Select-Object -Last 1
    }

    return ("{0}{1}/zabbix_agent-{1}-windows-amd64-openssl.msi" -f $base, $Version)
}
