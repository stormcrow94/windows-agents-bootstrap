<#
    main_installer.ps1 - compatibilidade com o nome antigo.

    O ponto de entrada agora e install.ps1. Este arquivo existe apenas para
    que atalhos e documentacao antigos continuem funcionando.
#>
& (Join-Path $PSScriptRoot 'install.ps1') @args
exit $LASTEXITCODE
