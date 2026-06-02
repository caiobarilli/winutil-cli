# 🖥️ winutil-cli

> Fork do [WinUtil (Chris Titus Tech)](https://github.com/ChrisTitusTech/winutil) sem interface gráfica — PowerShell puro, local ou via SSH.

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

## 🚀 Início rápido

```powershell
# Clonar e entrar no projeto
git clone git@github.com:caiobarilli/winutil-cli.git
cd winutil-cli

# Rodar como Administrador
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\winutil-cli.ps1
```

## ⚙️ Configurando no PATH

Para rodar `winutil` de qualquer lugar no terminal:

```powershell
# Adiciona o diretório ao PATH permanentemente
[System.Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";C:\winutil-cli",
    [System.EnvironmentVariableTarget]::Machine
)
```

Habilita execução de scripts no perfil do usuário:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

Adiciona o alias no perfil do PowerShell:

```powershell
Add-Content $PROFILE "`nSet-Alias winutil 'C:\winutil-cli\winutil-cli.ps1'"
```

Recarrega o perfil:

```powershell
. $PROFILE
```

Agora pode usar de qualquer lugar:

```powershell
winutil
winutil -Action audit
winutil -Action memory
```

---

## 🧰 Referência de comandos

### Audit
```powershell
winutil -Action audit
# Logs em C:\log\DD.MM.AAAA\
```

### Tweaks
```powershell
winutil -Action tweaks -Preset standard         # telemetria, DVR, serviços
winutil -Action tweaks -Preset standard -Undo   # reverte o preset
winutil -Action tweaks -Preset minimal          # só o essencial
winutil -Action tweaks -Preset advanced         # + OneDrive, widgets, Copilot
```

### Debloat
```powershell
winutil -Action debloat
# Remove 22 pacotes APPX (Xbox, Teams, Bing, Clipchamp...)
```

### DNS
```powershell
winutil -Action dns -Provider cloudflare
winutil -Action dns -Provider google
winutil -Action dns -Provider quad9
winutil -Action dns -Provider adguard_ads_trackers
winutil -Action dns -Provider dhcp                                                          # volta ao padrão
winutil -Action dns -Provider custom -PrimaryDNS <IP_PRIMARIO> -SecondaryDNS <IP_SECUNDARIO>
```

### Performance
```powershell
winutil -Action performance              # ativa Ultimate Performance
winutil -Action performance -State off   # volta ao Balanceado
```

### Install
```powershell
winutil -Action install -Apps "Git.Git"
winutil -Action install -Apps "Git.Git,Microsoft.VSCode,Docker.DockerDesktop"
```

### Memory
```powershell
winutil -Action memory
# Baixa WinMemoryCleaner.exe automaticamente na primeira execução
```

### Network (TShark)
```powershell
winutil -Action network                                    # interativo
winutil -Action network -Interface "Ethernet" -Duration 60
# Captura em C:\WinUtil\Captures\ — Relatório em C:\WinUtil\Reports\
```

### Exporter (Prometheus)
```powershell
winutil -Action exporter -SubAction install    # instala + inicia + tarefa agendada
winutil -Action exporter -SubAction status     # processo + tarefa agendada
winutil -Action exporter -SubAction start      # inicia o processo
winutil -Action exporter -SubAction stop       # para o processo
winutil -Action exporter -SubAction metrics    # verifica http://<HOSTNAME>:9182/metrics
winutil -Action exporter -SubAction firewall   # abre porta 9182
```

### Logs — leitura rápida
```powershell
ls C:\log\                                    # sessões disponíveis
cat C:\log\DD.MM.AAAA\01-sistema.txt          # bloco específico
cat C:\log\DD.MM.AAAA\03-processos.txt        # top processos
cat C:\log\DD.MM.AAAA\06-rede.txt             # conexões ativas

# Ver todos os blocos de uma sessão
Get-ChildItem C:\log\DD.MM.AAAA\ | ForEach-Object {
    Write-Host "=== $($_.Name) ===" -ForegroundColor Cyan
    Get-Content $_.FullName
    Write-Host
}

# Buscar processo nos logs
Select-String -Path C:\log\DD.MM.AAAA\03-processos.txt -Pattern "docker"
```

### Reverter / Limpar
```powershell
# Parar e remover windows_exporter
Stop-Process -Name windows_exporter -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'windows_exporter' -Confirm:$false -ErrorAction SilentlyContinue
$app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match 'windows_exporter' }
if ($app) { $app.Uninstall() }
```

---

## 📋 Menu interativo

```
winutil-cli
===========
[1] Audit       - Gerar log completo do sistema
[2] Tweaks      - Aplicar tweaks (Standard / Minimal / Advanced)
[3] Debloat     - Remover apps e APPX desnecessários
[4] DNS         - Trocar DNS
[5] Performance - Ativar/desativar Ultimate Performance
[6] Install     - Instalar apps via winget ou choco
[7] Memory      - Limpar memória RAM
[8] Network     - Captura de pacotes com TShark
[9] Exporter    - Instalar/gerenciar windows_exporter (Prometheus)
[0] Sair
```

---

## 🗂️ Estrutura do projeto

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
│   └── Invoke-Exporter.ps1
├── audit/
├── config/
├── functions/
│   ├── private/
│   └── public/
├── pester/
└── tools/
```

---

## 🗑️ O que foi removido

- Interface gráfica WPF inteira (`xaml/`, funções `WPF*`)
- Scripts de compilação e assinatura da GUI
- Temas, navegação de apps e outros configs exclusivos da interface
- Funções dependentes de `$sync` WPF

## 📦 O que foi mantido

- `config/` — JSONs de tweaks, apps, DNS, features e presets
- `functions/private/` — tweaks, instalação, serviços, registro e rede
- `functions/public/` — RemoveEdge
- `pester/configs.Tests.ps1` — testes de validação dos JSONs

## ⚡ O que foi adicionado

- `winutil-cli.ps1` — entry point com menu interativo e suporte a parâmetros CLI
- `scripts/` — actions segmentadas em arquivos independentes (`Invoke-*.ps1`)
- `audit/audit.ps1` — auditoria completa do sistema em 8 blocos
- `tools/WinMemoryCleaner.exe` — baixado automaticamente na primeira execução
- `pester/winutil-cli.Tests.ps1` — 14 testes Pester 5+ para o entry point

---

## 🔍 Audit — blocos gerados

| Arquivo | Conteúdo |
|---------|----------|
| `01-sistema.txt` | hostname, uptime, versão do Windows |
| `02-hardware.txt` | CPU, GPU, RAM, discos |
| `03-processos.txt` | top 30 processos por RAM |
| `04-servicos.txt` | serviços rodando |
| `05-startup.txt` | programas na inicialização |
| `06-rede.txt` | conexões ativas e portas abertas |
| `07-tarefas.txt` | tarefas agendadas ativas |
| `08-hyperv.txt` | estado das VMs Hyper-V |

---

## 🧪 Testes

```powershell
Import-Module "C:\Program Files\WindowsPowerShell\Modules\Pester\5.7.1\Pester.psd1" -Force
Invoke-Pester .\pester\configs.Tests.ps1
Invoke-Pester .\pester\winutil-cli.Tests.ps1
```

---

## 📊 Status das ações

| Ação | Status | Observação |
|------|--------|------------|
| audit | ✅ | 8 blocos de log gerados |
| tweaks standard | ✅ | 14 tweaks aplicados |
| tweaks advanced | ✅ | 18 tweaks aplicados |
| dns cloudflare | ✅ | Aplicado nos adaptadores ativos |
| dns custom | ✅ | Suporte a DNS local (ex: AdGuard Home) |
| memory | ✅ | Download automático + limpeza |
| performance | ✅ | GUID detectado dinamicamente via `powercfg /list` |
| debloat | ✅ | 22 pacotes APPX definidos |
| install | ✅ | Testado com Git.Git via winget |
| network | ✅ | TShark + relatório em `C:\WinUtil\Reports\` |
| exporter | ✅ | Start-Process + tarefa agendada no boot |
| tweaks -Undo | ✅ | Reverte tweaks para valores originais |

---

## 🗺️ Roadmap

- [x] Entry point `winutil-cli.ps1` com menu CLI
- [x] Audit logs em `C:\log\DD.MM.AAAA\`
- [x] DNS via parâmetro com suporte a provider custom
- [x] Limpeza de RAM via WinMemoryCleaner com download automático
- [x] Tweaks Standard e Advanced testados
- [x] Performance — GUID detectado dinamicamente
- [x] Debloat — 22 pacotes APPX definidos
- [x] Testes Pester 14/14 para o entry point
- [x] Install testado via winget
- [x] Network — captura TShark com relatório
- [x] Exporter — windows_exporter para Prometheus via Start-Process
- [x] Testes automatizados no CI/CD (GitHub Actions)
- [x] Suporte a `-Action tweaks -Undo` para reverter tweaks
- [x] Segmentação do entry point em `scripts/Invoke-*.ps1`

---

## 🙏 Créditos

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) — projeto base
- [IgorMundstein/WinMemoryCleaner](https://github.com/IgorMundstein/WinMemoryCleaner) — limpeza de RAM