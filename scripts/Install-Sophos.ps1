<#
    Install-Sophos.ps1 - instala o Sophos Endpoint pelo bootstrapper do Central.

    A fonte padrao e o repositorio interno configurado em config/settings.psd1
    (Sophos.Repository + InstallerName). O SophosSetup.exe e um bootstrapper:
    ele baixa o produto do CDN da Sophos, portanto o host precisa de acesso a
    internet. O token do tenant so e usado para baixar o bootstrapper uma vez,
    no servidor que publica o arquivo no share.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1 -Force
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1 -DryRun
        powershell -ExecutionPolicy Bypass -File .\scripts\Install-Sophos.ps1 -SourcePath D:\temp\SophosSetup.exe
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$SourcePath,
    [switch]$Force,
    [switch]$DryRun
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

    if (-not $Force -and -not $DryRun -and $installed -and $mcs) {
        $version = ($installed | Select-Object -First 1).DisplayVersion
        Write-Log -Message "Sophos Endpoint ja instalado (versao $version) e MCS Agent presente. Nada a fazer." -Level OK
        exit 0
    }

    # ---------------------------------------------------------------
    # Resolucao da fonte: -SourcePath -> repositorio interno -> cache -> FallbackUrl
    # ---------------------------------------------------------------
    $exePath = Join-Path $config.Common.CacheDir 'SophosSetup.exe'

    function Get-FileSha256 {
        param([string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $source = $null

    if ($SourcePath) {
        if (-not (Test-Path -LiteralPath $SourcePath)) { throw "SourcePath nao encontrado: $SourcePath" }
        $source = (Resolve-Path -LiteralPath $SourcePath).Path
        Write-Log -Message "Fonte informada manualmente: $source" -Level INFO
    }
    elseif ($s.Repository) {
        $repoFile = Join-Path $s.Repository $s.InstallerName
        if (Test-Path -LiteralPath $repoFile) {
            $source = $repoFile
            Write-Log -Message "Fonte: repositorio interno $repoFile" -Level INFO
        }
        else {
            Write-Log -Message "Repositorio interno indisponivel: $repoFile" -Level WARN
        }
    }

    if (-not $source -and (Test-Path -LiteralPath $exePath)) {
        $source = $exePath
        Write-Log -Message "Fonte: cache local $exePath" -Level INFO
    }

    if (-not $source) {
        if ($s.FallbackUrl) {
            Write-Log -Message 'Baixando do FallbackUrl...' -Level STEP
            $null = Invoke-VtxDownload -Url $s.FallbackUrl -Destination $exePath
            $source = $exePath
        }
        else {
            throw 'Nenhuma fonte disponivel: repositorio interno inacessivel, sem cache e sem FallbackUrl.'
        }
    }

    if ($source -ne $exePath) {
        $parent = Split-Path -Parent $exePath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

        $reuseCache = $false
        if (-not $Force -and (Test-Path -LiteralPath $exePath)) {
            if ((Get-FileSha256 -Path $exePath) -eq (Get-FileSha256 -Path $source)) {
                Write-Log -Message 'Cache local identico a fonte; reutilizando.' -Level INFO
                $reuseCache = $true
            }
        }

        if ($reuseCache) {
            $source = $exePath
        }
        else {
            Copy-Item -LiteralPath $source -Destination $exePath -Force
            $source = $exePath
            Write-Log -Message ("Copiado para o cache ({0:N0} bytes)" -f (Get-Item -LiteralPath $exePath).Length) -Level OK
        }
    }

    $exePath = $source

    # ---------------------------------------------------------------
    # Integridade: hash configurado + assinatura Authenticode
    # ---------------------------------------------------------------
    $hash = Get-FileSha256 -Path $exePath
    if ($s.Sha256) {
        if ($hash -ne $s.Sha256.ToLowerInvariant()) {
            throw "Hash SHA256 nao confere. Esperado $($s.Sha256), obtido $hash. Se a troca do instalador foi intencional, atualize Sophos.Sha256 no settings.psd1."
        }
        Write-Log -Message 'SHA256 confere com o settings.psd1.' -Level OK
    }
    else {
        Write-Log -Message "SHA256 do binario: $hash (sem hash de referencia configurado)." -Level INFO
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $exePath
    if ($signature.Status -ne 'Valid') {
        throw "Assinatura digital invalida em $exePath (status: $($signature.Status))."
    }
    if ($signature.SignerCertificate.Subject -notmatch 'O=Sophos Ltd') {
        throw "Signatario inesperado em $exePath : $($signature.SignerCertificate.Subject). Esperado Sophos Ltd."
    }
    Write-Log -Message "Assinatura verificada: $($signature.SignerCertificate.Subject)" -Level INFO

    if ($DryRun) {
        Write-Log -Message 'DryRun: fonte, hash e assinatura validados; nada foi instalado.' -Level OK
        exit 0
    }

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
