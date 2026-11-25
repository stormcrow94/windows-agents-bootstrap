<#
    Configuracao central dos instaladores Vantix.

    Edite este arquivo em vez de alterar os scripts.
    Os caminhos de cache, log e backup sao criados automaticamente.
#>
@{
    Common = @{
        LogDir    = 'C:\ProgramData\Vantix\install-logs'
        CacheDir  = 'C:\ProgramData\Vantix\cache'
        BackupDir = 'C:\ProgramData\Vantix\backup'
    }

    Zabbix = @{
        # Branch do servidor Zabbix (7.0, 7.4, ...). O patch e resolvido no CDN.
        Branch         = '7.0'

        # 'latest' = ultimo patch do branch; ou fixe '7.0.32'.
        AgentVersion   = 'latest'

        # Override total da URL do MSI (deixe vazio para resolver no CDN).
        StaticUrl      = ''

        # Servidor/proxy e porta. Se ja existir configuracao no host,
        # ela e preservada (PreserveExistingServer = $true).
        Server         = '10.130.3.201'
        ServerActive   = '10.130.3.201'
        PreserveExistingServer = $true

        HostMetadata   = 'Windows'
        ListenPort     = 10050
        StartAgents    = 5
        Timeout        = 30
        DebugLevel     = 3
    }

    Wazuh = @{
        # Deve ser igual ou inferior a versao do manager (4.14.8 hoje).
        Version            = '4.14.8'
        Manager            = 'wazuh.vantix.com.br'
        ManagerPort        = 1514
        RegistrationServer = 'wazuh.vantix.com.br'
        RegistrationPort   = 1515
        AgentGroup         = 'COMMCENTER'
        Protocol           = 'tcp'
    }

    Sophos = @{
        # Repositorio interno (share SMB) com o bootstrapper baixado do Sophos Central.
        # Deixe Repository vazio para pular a fonte interna.
        Repository    = '\\10.130.2.10\Implatacao_Sophos'
        InstallerName = 'SophosSetup.exe'

        # Hash SHA256 esperado do binario (vazio = nao valida).
        # Ao trocar o instalador no share, atualize este valor.
        Sha256        = '37dd568aef56c24f799c8b886c15ea2f56490259ef7bf9c2472ea209d0d07bf6'

        # Fonte alternativa (URL) usada somente se o share estiver indisponivel.
        # Deixe vazio para exigir o repositorio interno.
        FallbackUrl   = ''
    }
}
