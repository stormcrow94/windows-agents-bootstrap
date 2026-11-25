<#
    Install-Sophos.ps1 - instala o Sophos Endpoint pelo bootstrapper do Central.

    O SophosSetup.exe e um bootstrapper: ele baixa o produto do CDN da Sophos,
    portanto o host precisa de acesso a internet. O token do tenant vem embutido
    na URL de download gerada no Sophos Central.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1 -Force
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
$s = $config.Sophos
$log = Initialize-VtxLog -Name 'sophos' -LogDir $config.Common.LogDir

$exitCode = 0
$serviceNames = @('Sophos MCS Agent', 'Sophos File Scanner Service', 'Sophos AutoUpdate Service')

try {
    Assert-Administrator
    Write-Log -Message 'Iniciando instalacao do Sophos Endpoint' -Level STEP

    $installed = Get-InstalledProduct -NamePattern '^Sophos Endpoint Agent'
    $mcs = Get-Service -Name 'Sophos MCS Agent' -ErrorAction SilentlyContinue

    if (-not $Force -and $installed -and $mcs) {
        $version = ($installed | Select-Object -First 1).DisplayVersion
        Write-Log -Message "Sophos Endpoint ja instalado (versao $version) e MCS Agent presente. Nada a fazer." -Level OK
        exit 0
    }

    # ---------------------------------------------------------------
    # Download e validacao do binario
    # ---------------------------------------------------------------
    $exePath = Join-Path $config.Common.CacheDir 'SophosSetup.exe'

    if (-not $Force -and (Test-Path -LiteralPath $exePath) -and (Get-Item -LiteralPath $exePath).Length -gt 1MB) {
        Write-Log -Message "Instalador em cache: $exePath" -Level INFO
    }
    else {
        Write-Log -Message "Baixando $($s.InstallerUrl)" -Level STEP
        $size = Invoke-VtxDownload -Url $s.InstallerUrl -Destination $exePath
        Write-Log -Message ("Download concluido ({0:N0} bytes)" -f $size) -Level OK
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $exePath
    if ($signature.Status -ne 'Valid') {
        throw "Assinatura digital invalida em $exePath (status: $($signature.Status))."
    }
    Write-Log -Message "Assinatura verificada: $($signature.SignerCertificate.Subject)" -Level INFO

    # ---------------------------------------------------------------
    # Instalacao silenciosa
    # ---------------------------------------------------------------
    Write-Log -Message 'Executando SophosSetup.exe --quiet' -Level STEP
    $proc = Start-Process -FilePath $exePath -ArgumentList '--quiet' -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 3010) {
        Write-Log -Message 'Instalador retornou 3010 (reinicio necessario).' -Level WARN
    }
    elseif ($proc.ExitCode -ne 0) {
        throw "SophosSetup.exe retornou exit $($proc.ExitCode)."
    }

    # ---------------------------------------------------------------
    # Validacao dos servicos
    # ---------------------------------------------------------------
    $running = 0
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Date) -lt $deadline) {
        $running = 0
        foreach ($name in $serviceNames) {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { $running++ }
        }
        if ($running -ge 2) { break }
        Start-Sleep -Seconds 10
    }

    if ($running -lt 2) {
        throw "Sophos instalado, mas os servicos nao subiram (running=$running de $($serviceNames.Count))."
    }

    $version = $null
    $product = Get-InstalledProduct -NamePattern '^Sophos Endpoint Agent'
    if ($product) { $version = ($product | Select-Object -First 1).DisplayVersion }

    Write-Log -Message "Sophos Endpoint instalado (versao $version); $running servicos ativos." -Level OK
    Write-Log -Message 'Sophos Endpoint instalado e validado com sucesso.' -Level OK
}
catch {
    Write-Log -Message ("Falha: " + $_.Exception.Message) -Level ERROR
    $exitCode = 1
}

exit $exitCode
