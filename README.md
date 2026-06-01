# winutil-cli

Fork do [WinUtil (Chris Titus Tech)](https://github.com/ChrisTitusTech/winutil) focado em uso via linha de comando — sem interface gráfica, sem dependências de WPF ou Electron. Tudo roda via PowerShell, local ou remotamente via SSH.

## O que foi removido

- Interface gráfica WPF inteira (`xaml/`, funções `WPF*`)
- Scripts de compilação e assinatura da GUI
- Temas, navegação de apps e outros configs exclusivos da interface

## O que foi mantido

- `config/` — JSONs de tweaks, apps, DNS, features e presets
- `functions/private/` — funções de tweaks, instalação, serviços, registro e rede
- `functions/public/` — AutoRun, RemoveEdge

## O que foi adicionado

- `audit/audit.ps1` — auditoria completa do sistema em blocos, salva logs em `C:\log\DD.MM.AAAA\`

## Uso

> Requer PowerShell como Administrador.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Audit

```powershell
C:\caminho\para\winutil-cli\audit\audit.ps1
```

Gera os seguintes arquivos em `C:\log\DD.MM.AAAA\`:

- `01-sistema.txt` — hostname, uptime, versão do Windows
- `02-hardware.txt` — CPU, GPU, RAM, discos
- `03-processos.txt` — top 30 processos por consumo de RAM
- `04-servicos.txt` — serviços rodando
- `05-startup.txt` — programas na inicialização
- `06-rede.txt` — conexões ativas e portas abertas
- `07-tarefas.txt` — tarefas agendadas ativas
- `08-hyperv.txt` — estado das VMs Hyper-V

## Roadmap

- [ ] Entry point `winutil-cli.ps1` com menu CLI
- [ ] Integração dos tweaks via parâmetros (`--tweaks`, `--dns`, `--audit`)
- [ ] Suporte a presets via CLI (`--preset standard`)
- [ ] Debloat e remoção de APPX via terminal

## Créditos

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) — projeto base
