# 🖥️ winutil-cli

> Fork of [WinUtil (Chris Titus Tech)](https://github.com/ChrisTitusTech/winutil) without a graphical interface — pure PowerShell, local or via SSH.

```
  ██╗    ██╗██╗███╗   ██╗██╗   ██╗████████╗██╗██╗         ██████╗██╗     ██╗
  ██║    ██║██║████╗  ██║██║   ██║╚══██╔══╝██║██║        ██╔════╝██║     ██║
  ██║ █╗ ██║██║██╔██╗ ██║██║   ██║   ██║   ██║██║        ██║     ██║     ██║
  ██║███╗██║██║██║╚██╗██║██║   ██║   ██║   ██║██║        ██║     ██║     ██║
  ╚███╔███╔╝██║██║ ╚████║╚██████╔╝   ██║   ██║███████╗   ╚██████╗███████╗██║
   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚══════╝    ╚═════╝╚══════╝╚═╝
```
[![Pester Tests](https://github.com/caiobarilli/winutil-cli/actions/workflows/tests.yml/badge.svg)](https://github.com/caiobarilli/winutil-cli/actions/workflows/tests.yml)

---

## 🚀 Quick start

```powershell
# Clone and enter the project
git clone git@github.com:caiobarilli/winutil-cli.git
cd winutil-cli

# Run as Administrator
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\winutil-cli.ps1
```

## ⚙️ Adding to PATH

To run `winutil` from anywhere in the terminal:

```powershell
# Add the directory to PATH permanently
[System.Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";C:\winutil-cli",
    [System.EnvironmentVariableTarget]::Machine
)
```

Enable script execution for the current user profile:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

Add the alias to the PowerShell profile:

```powershell
Add-Content $PROFILE "`nSet-Alias winutil 'C:\winutil-cli\winutil-cli.ps1'"
```

Reload the profile:

```powershell
. $PROFILE
```

Now you can use it from anywhere:

```powershell
winutil
winutil -Action audit
winutil -Action memory
```

---

## 🧰 Command reference

### Audit
```powershell
winutil -Action audit
# Logs saved to C:\log\DD.MM.YYYY\
```

### Tweaks
```powershell
winutil -Action tweaks -Preset standard         # telemetry, DVR, services
winutil -Action tweaks -Preset standard -Undo   # revert the preset
winutil -Action tweaks -Preset minimal          # essentials only
winutil -Action tweaks -Preset advanced         # + OneDrive, widgets, Copilot
```

### Debloat
```powershell
winutil -Action debloat
# Removes 22 APPX packages (Xbox, Teams, Bing, Clipchamp...)
```

### DNS
```powershell
winutil -Action dns -Provider cloudflare
winutil -Action dns -Provider google
winutil -Action dns -Provider quad9
winutil -Action dns -Provider adguard_ads_trackers
winutil -Action dns -Provider dhcp                                                          # restore default
winutil -Action dns -Provider custom -PrimaryDNS <PRIMARY_IP> -SecondaryDNS <SECONDARY_IP>
```

### Performance
```powershell
winutil -Action performance              # enable Ultimate Performance
winutil -Action performance -State off   # restore Balanced plan
```

### Install
```powershell
winutil -Action install -Apps "Git.Git"
winutil -Action install -Apps "Git.Git,Microsoft.VSCode,Docker.DockerDesktop"
```

### Memory
```powershell
winutil -Action memory
# Downloads WinMemoryCleaner.exe automatically on first run
```

### Network (TShark)
```powershell
winutil -Action network                                    # interactive
winutil -Action network -Interface "Ethernet" -Duration 60
# Captures saved to C:\WinUtil\Captures\ — Reports saved to C:\WinUtil\Reports\
```

### Exporter (Prometheus)
```powershell
winutil -Action exporter -SubAction install    # install + start + scheduled task
winutil -Action exporter -SubAction status     # process + scheduled task status
winutil -Action exporter -SubAction start      # start the process
winutil -Action exporter -SubAction stop       # stop the process
winutil -Action exporter -SubAction metrics    # check http://<HOSTNAME>:9182/metrics
winutil -Action exporter -SubAction firewall   # open port 9182
```

### Processes
```powershell
winutil -Action processes
# Displays top 30 processes by RAM usage
```

### Logs — quick read
```powershell
ls C:\log\                                      # available sessions
cat C:\log\DD.MM.YYYY\01-system.txt             # specific block
cat C:\log\DD.MM.YYYY\03-processes.txt          # top processes
cat C:\log\DD.MM.YYYY\06-network.txt            # active connections

# View all blocks from a session
Get-ChildItem C:\log\DD.MM.YYYY\ | ForEach-Object {
    Write-Host "=== $($_.Name) ===" -ForegroundColor Cyan
    Get-Content $_.FullName
    Write-Host
}

# Search for a process in the logs
Select-String -Path C:\log\DD.MM.YYYY\03-processes.txt -Pattern "docker"
```

### Revert / Clean up
```powershell
# Stop and remove windows_exporter
Stop-Process -Name windows_exporter -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'windows_exporter' -Confirm:$false -ErrorAction SilentlyContinue
$app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match 'windows_exporter' }
if ($app) { $app.Uninstall() }
```

---

## 📋 Interactive menu

```
winutil-cli
===========
[1] Audit       - Generate full system log
[2] Tweaks      - Apply tweaks (Standard / Minimal / Advanced)
[3] Debloat     - Remove unnecessary APPX packages
[4] DNS         - Change DNS
[5] Performance - Enable/disable Ultimate Performance
[6] Install     - Install apps via winget
[7] Memory      - Clean RAM
[8] Network     - Packet capture with TShark
[9] Exporter    - Install/manage windows_exporter (Prometheus)
[10] Processes  - Show top 30 processes by RAM
[0] Exit
```

---

## 🗂️ Project structure

```
winutil-cli/
├── winutil-cli.ps1          ← entry point: params, encoding, admin check, load, dispatch
├── scripts/
│   ├── Invoke-Audit.ps1
│   ├── Invoke-Tweaks.ps1
│   ├── Invoke-Debloat.ps1
│   ├── Invoke-DNS.ps1
│   ├── Invoke-Performance.ps1
│   ├── Invoke-Install.ps1
│   ├── Invoke-Memory.ps1
│   ├── Invoke-Network.ps1
│   ├── Invoke-Exporter.ps1
│   └── Invoke-Processes.ps1
├── audit/
├── config/
├── functions/
│   ├── private/
│   └── public/
├── pester/
└── tools/
```

---

## 🗑️ What was removed

- Full WPF graphical interface (`xaml/`, `WPF*` functions)
- GUI compilation and signing scripts
- Themes, app navigation and other GUI-only configs
- Functions depending on the WPF `$sync` object

## 📦 What was kept

- `config/` — tweaks, apps, DNS, features and preset JSONs
- `functions/private/` — tweaks, install, services, registry and network
- `functions/public/` — RemoveEdge
- `pester/configs.Tests.ps1` — JSON validation tests

## ⚡ What was added

- `winutil-cli.ps1` — entry point with interactive menu and CLI parameter support
- `scripts/` — actions split into independent modules (`Invoke-*.ps1`)
- `audit/audit.ps1` — full system audit in 8 blocks
- `tools/WinMemoryCleaner.exe` — downloaded automatically on first run
- `scripts/Invoke-Processes.ps1` — lists top 30 processes by RAM usage directly in the terminal
- `pester/winutil-cli.Tests.ps1` — 18 Pester 5+ tests for the entry point

---

## 🔍 Audit — generated blocks

| File | Content |
|------|---------|
| `01-system.txt` | hostname, uptime, Windows version |
| `02-hardware.txt` | CPU, GPU, RAM, disks |
| `03-processes.txt` | top 30 processes by RAM |
| `04-services.txt` | running services |
| `05-startup.txt` | startup programs |
| `06-network.txt` | active connections and open ports |
| `07-tasks.txt` | active scheduled tasks |
| `08-hyperv.txt` | Hyper-V VM state |

---

## 🧪 Tests

```powershell
Import-Module "C:\Program Files\WindowsPowerShell\Modules\Pester\5.7.1\Pester.psd1" -Force
Invoke-Pester .\pester\ -Output Detailed
```

---

## 📊 Action status

| Action | Status | Notes |
|--------|--------|-------|
| audit | ✅ | 8 log blocks generated |
| tweaks standard | ✅ | 14 tweaks applied |
| tweaks advanced | ✅ | 18 tweaks applied |
| dns cloudflare | ✅ | Applied on active adapters |
| dns custom | ✅ | Local DNS support (e.g. AdGuard Home) |
| memory | ✅ | Auto-download + cleanup |
| performance | ✅ | GUID detected dynamically via `powercfg /list` |
| debloat | ✅ | 22 APPX packages defined |
| install | ✅ | Tested with Git.Git via winget |
| network | ✅ | TShark + report in `C:\WinUtil\Reports\` |
| exporter | ✅ | Start-Process + scheduled task at boot |
| tweaks -Undo | ✅ | Reverts tweaks to original values |
| processes | ✅ | Top 30 processes by RAM displayed in terminal |

---

## 🗺️ Roadmap

- [x] `winutil-cli.ps1` entry point with CLI menu
- [x] Audit logs in `C:\log\DD.MM.YYYY\`
- [x] DNS via parameter with custom provider support
- [x] RAM cleanup via WinMemoryCleaner with auto-download
- [x] Tweaks Standard and Advanced tested
- [x] Performance — GUID detected dynamically
- [x] Debloat — 22 APPX packages defined
- [x] Pester 18/18 tests passing
- [x] Install tested via winget
- [x] Network — TShark capture with report
- [x] Exporter — windows_exporter for Prometheus via Start-Process
- [x] Automated tests in CI/CD (GitHub Actions)
- [x] `-Action tweaks -Undo` support to revert tweaks
- [x] Entry point segmented into `scripts/Invoke-*.ps1`
- [x] Processes — top 30 processes by RAM displayed in terminal

---

## 🙏 Credits

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) — base project
- [IgorMundstein/WinMemoryCleaner](https://github.com/IgorMundstein/WinMemoryCleaner) — RAM cleanup