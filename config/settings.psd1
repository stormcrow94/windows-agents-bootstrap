@{
    # Zabbix Agent (Windows MSI)
    ZabbixMsiUrl           = 'https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.25/zabbix_agent-7.0.25-windows-amd64-openssl.msi'
    ZabbixServer           = '10.130.3.201'
    ZabbixServerActive     = '10.130.3.201'
    ZabbixServerPort       = '10051'
    ZabbixAgentPort        = '10050'

    # Wazuh Agent
    WazuhMsiUrl            = 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi'
    WazuhManager           = 'wazuh.vantix.com.br'
    WazuhVersion           = '4.14.0'
    WazuhRevision          = '1'

    # Sophos (URL only; installer downloaded at runtime)
    SophosInstallerUrl     = 'https://api.stn100gru.ctr.sophos.com/api/download/REMOVED_TOKEN/SophosSetup.exe'
    SophosInstallArgs      = '--quiet'

    # Active Directory join (optional defaults; empty = prompt)
    DefaultDomain          = ''
    DefaultDomainOuPath    = ''

    # General
    LogDirName             = 'logs'
    CheckInternet          = $true
    NetworkTimeoutSeconds  = 30
    AutoBackup               = $true
    ContinueOnWarning      = $true
}
