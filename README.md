# PowerShell install applications (Windows)

PowerShell 5.1+ toolkit to install or remove agents (Zabbix, Wazuh, Sophos), rename the computer, and join Active Directory. The layout mirrors the Linux project [shell-install-applications-script](https://github.com/stormcrow94/shell-install-applications-script): central settings, shared helpers, logs, and a main menu similar to `installer.sh`.

## Prerequisites

- Windows 10 / 11 or Windows Server with **PowerShell 5.1** or newer
- **Run as Administrator** ( `main_installer.ps1` can relaunch elevated )
- Network access to download official MSIs / Sophos setup (URLs in `config\settings.psd1`)
- For the current session: `Set-ExecutionPolicy -Scope Process Bypass -Force` if execution policy blocks scripts

## Quick start

1. Copy or clone the repository on the target machine.
2. Open an elevated PowerShell and `cd` to the repository folder.
3. Run `.\main_installer.ps1`.
4. Choose an action from the menu and follow prompts where applicable.

## Main menu (`main_installer.ps1`)

| Option | Action |
|--------|--------|
| 1 | Install Zabbix Agent |
| 2 | Configure computer name (`hostname.ps1`) |
| 3 | Install Wazuh Agent |
| 4 | Install Sophos |
| 5 | Join Active Directory (`register_domain.ps1`) |
| 6 | Full install (hostname script, then Zabbix, Wazuh, optional Sophos & domain) |
| 7 | Edit `config\settings.psd1` in Notepad |
| 8 | List and display recent log files under `logs\` |
| 9 | Remove Zabbix Agent |
| 0 | Exit |

## Configuration

Edit **`config\settings.psd1`** (or use menu option **7**):

- **Zabbix**: `ZabbixMsiUrl`, `ZabbixServer`, `ZabbixServerActive` (defaults include Zabbix **7.0.25** Windows MSI).
- **Wazuh**: `WazuhMsiUrl`, `WazuhManager` (defaults: agent **4.14.0-1**, manager `wazuh.vantix.com.br`).
- **Sophos**: `SophosInstallerUrl`, `SophosInstallArgs` (no large installer committed to git; download at runtime).
- **Domain**: optional `DefaultDomain`, `DefaultDomainOuPath` for prompts in `register_domain.ps1`.
- **General**: `LogDirName`, `CheckInternet`, `NetworkTimeoutSeconds`, `AutoBackup`, `ContinueOnWarning`.

Runtime logs are written under **`logs\`** (ignored by git via `.gitignore`).

## Scripts

| File | Purpose |
|------|---------|
| `main_installer.ps1` | Interactive menu, elevation check, timeouts |
| `lib\Common.ps1` | Settings import, logging, prompts, internet check |
| `install_zabbix_silent.ps1` | Download MSI, silent install, tune config, start service. Parameters: `-ZabbixServer`, `-ZabbixServerActive`, `-MsiUrl` |
| `install_wazuh.ps1` | Download MSI, `msiexec` silent install, start service. Parameters: `-WazuhManager`, `-MsiUrl` |
| `install_sophos.ps1` | Download `SophosSetup.exe`, silent install from settings |
| `hostname.ps1` | `Rename-Computer`; restart required; warns if already domain-joined |
| `register_domain.ps1` | `Add-Computer` with `Get-Credential`; optional OU; reboot required to finish |
| `remove_zabbix.ps1` | Uninstall Zabbix packages, remove services and common registry keys |

## Windows-specific notes

- **Computer rename** and **domain join** normally require a **reboot** to complete.
- **Domain-joined** machines may block or complicate renaming; use domain admin processes when needed.
- **AD join** needs working **DNS** to the domain, reachable DCs (ports such as 88, 389/636, 445, RPC), and an account with rights to create or reset the computer account. If the PC is already in a domain, the script exits with guidance instead of joining again.

## Repository layout

```text
.
├── main_installer.ps1
├── install_zabbix_silent.ps1
├── install_wazuh.ps1
├── install_sophos.ps1
├── remove_zabbix.ps1
├── hostname.ps1
├── register_domain.ps1
├── config
│   └── settings.psd1
├── lib
│   └── Common.ps1
└── logs          (created at runtime)
```
