#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point do winutil-cli — fork CLI do WinUtil (ChrisTitusTech), sem GUI/WPF.

.DESCRIPTION
    Roda local ou via SSH, em PowerShell 5.1 ou 7+.
    Dois modos:
      - Interativo: sem parametros, exibe menu numerado.
      - Parametro : via -Action para uso em CLI/SSH.

.EXAMPLE
    .\winutil-cli.ps1
    .\winutil-cli.ps1 -Action audit
    .\winutil-cli.ps1 -Action tweaks -Preset standard
    .\winutil-cli.ps1 -Action dns -Provider cloudflare
    .\winutil-cli.ps1 -Action debloat
    .\winutil-cli.ps1 -Action performance
    .\winutil-cli.ps1 -Action install -Apps "Git.Git,Microsoft.VSCode"
#>

[CmdletBinding()]
param(
    [ValidateSet('audit', 'tweaks', 'debloat', 'dns', 'performance', 'install')]
    [string]$Action,

    [ValidateSet('standard', 'minimal', 'advanced')]
    [string]$Preset = 'standard',

    [string]$Provider,

    [string]$Apps
)

# ============================================================
# ENCODING — UTF-8 sem BOM (vale para PS 5.1 e 7+)
# ============================================================
$OutputEncoding             = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding    = [System.Text.UTF8Encoding]::new($false)

# ============================================================
# STATUS — mensagens padronizadas no terminal
# ============================================================
function Write-Status {
    param(
        [ValidateSet('OK', 'ERRO', 'AVISO', 'INFO')]
        [string]$Level,
        [string]$Message
    )
    $map = @{
        OK    = @{ Tag = '[ OK ]';    Color = 'Green'  }
        ERRO  = @{ Tag = '[ ERRO ]';  Color = 'Red'    }
        AVISO = @{ Tag = '[ AVISO ]'; Color = 'Yellow' }
        INFO  = @{ Tag = '[ INFO ]';  Color = 'Gray'   }
    }
    Write-Host "$($map[$Level].Tag) $Message" -ForegroundColor $map[$Level].Color
}

# ============================================================
# PRIVILEGIOS — exige Administrador
# ============================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Status ERRO "Este script precisa ser executado como Administrador."
    Write-Status INFO "Abra o terminal com 'Executar como administrador' e rode de novo."
    exit 1
}

# ============================================================
# CARGA DAS FUNCOES — dot-source de private/ e public/
# ============================================================
$root = $PSScriptRoot

$funcDirs = @(
    (Join-Path $root 'functions\private'),
    (Join-Path $root 'functions\public')
)

foreach ($dir in $funcDirs) {
    if (-not (Test-Path $dir)) {
        Write-Status AVISO "Diretorio nao encontrado: $dir"
        continue
    }
    Get-ChildItem -Path $dir -Filter '*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        } catch {
            Write-Status ERRO "Falha ao carregar $($_.Name): $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CONFIGS — monta o hashtable global $sync que as funcoes usam
# As funcoes do projeto leem de $sync.configs.<nome> (ex: $sync.configs.dns)
# ============================================================
$global:sync = [hashtable]::Synchronized(@{})
$sync.configs = @{}

$configPath = Join-Path $root 'config'

foreach ($name in 'dns', 'tweaks', 'preset', 'feature', 'applications') {
    $file = Join-Path $configPath "$name.json"
    if (Test-Path $file) {
        try {
            $sync.configs.$name = Get-Content -Path $file -Raw | ConvertFrom-Json
        } catch {
            Write-Status AVISO "JSON invalido em $name.json: $($_.Exception.Message)"
        }
    } else {
        Write-Status AVISO "Config nao encontrado: $name.json"
    }
}

# ============================================================
# ACAO: AUDIT — roda o script de auditoria (salva em C:\log\DD.MM.AAAA)
# ============================================================
function Invoke-ActionAudit {
    $auditScript = Join-Path $root 'audit\audit.ps1'
    if (-not (Test-Path $auditScript)) {
        Write-Status ERRO "audit.ps1 nao encontrado em $auditScript"
        return
    }
    Write-Status INFO "Gerando auditoria do sistema..."
    & $auditScript
    Write-Status OK "Auditoria concluida."
}

# ============================================================
# ACAO: TWEAKS — aplica um preset (lista de checkboxes do preset.json)
# Cada item do preset eh repassado para Invoke-WinUtilTweaks.
# TODO: validar que Invoke-WinUtilTweaks roda sem dependencia de GUI/WPF
#       no fluxo CLI (so o cabecalho da funcao foi inspecionado).
# ============================================================
function Invoke-ActionTweaks {
    param([string]$Preset)

    # preset.json usa chaves capitalizadas (Standard / Minimal / Advanced)
    $key = (Get-Culture).TextInfo.ToTitleCase($Preset.ToLower())

    $list = $sync.configs.preset.$key
    if (-not $list) {
        Write-Status ERRO "Preset '$key' nao encontrado em preset.json"
        return
    }

    Write-Status INFO "Aplicando preset '$key' ($($list.Count) tweaks)..."
    foreach ($checkbox in $list) {
        try {
            Invoke-WinUtilTweaks -CheckBox $checkbox
            Write-Status OK $checkbox
        } catch {
            Write-Status ERRO "$checkbox -> $($_.Exception.Message)"
        }
    }
    Write-Status OK "Preset '$key' aplicado."
}

# ============================================================
# ACAO: DEBLOAT — remove APPX desnecessarios
# Remove-WinUtilAPPX recebe um nome de pacote por vez.
# TODO: preencher a lista de pacotes a remover. Nenhum nome foi
#       definido no material do projeto, entao a lista vai vazia
#       de proposito (nao chutar pacotes).
# ============================================================
function Invoke-ActionDebloat {
    $appxToRemove = @(
        # TODO: adicionar os nomes dos pacotes APPX, ex:
        # "Microsoft.Microsoft3DViewer",
        # "Microsoft.BingWeather"
    )

    if ($appxToRemove.Count -eq 0) {
        Write-Status AVISO "Nenhum pacote definido para remocao (ver TODO em Invoke-ActionDebloat)."
        return
    }

    Write-Status INFO "Removendo $($appxToRemove.Count) pacote(s) APPX..."
    foreach ($name in $appxToRemove) {
        try {
            Remove-WinUtilAPPX -Name $name
            Write-Status OK $name
        } catch {
            Write-Status ERRO "$name -> $($_.Exception.Message)"
        }
    }
    Write-Status OK "Debloat concluido."
}

# ============================================================
# ACAO: DNS — troca o DNS via Set-WinUtilDNS (le do dns.json)
# ============================================================
function Invoke-ActionDNS {
    param([string]$Provider)

    if (-not $Provider) {
        Write-Status ERRO "Informe o provedor com -Provider (ex: cloudflare, google, quad9)."
        return
    }

    # valida contra as chaves do dns.json (acesso eh case-insensitive)
    $valid = @($sync.configs.dns.PSObject.Properties.Name)
    if ($Provider -notin $valid -and $Provider -notin @('Default', 'DHCP')) {
        Write-Status ERRO "Provedor '$Provider' nao existe no dns.json."
        Write-Status INFO  "Disponiveis: $($valid -join ', ')"
        return
    }

    Write-Status INFO "Aplicando DNS '$Provider'..."
    try {
        Set-WinUtilDNS -DNSProvider $Provider
        Write-Status OK "DNS '$Provider' aplicado."
    } catch {
        Write-Status ERRO $_.Exception.Message
    }
}

# ============================================================
# ACAO: PERFORMANCE — Ultimate Performance via powercfg
# Nao existe funcao no projeto; usa o GUID oficial da Microsoft.
# ============================================================
function Invoke-ActionPerformance {
    param(
        [ValidateSet('on', 'off')]
        [string]$State = 'on'
    )

    # GUIDs oficiais de plano de energia (Microsoft)
    $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'

    if ($State -eq 'on') {
        Write-Status INFO "Ativando Ultimate Performance..."
        try {
            # duplica o esquema (adiciona a lista) e ativa
            powercfg -duplicatescheme $ultimateGuid | Out-Null
            powercfg -setactive $ultimateGuid
            Write-Status OK "Ultimate Performance ativado."
        } catch {
            Write-Status ERRO $_.Exception.Message
        }
    } else {
        Write-Status INFO "Voltando para o plano Balanceado..."
        try {
            powercfg -setactive $balancedGuid
            Write-Status OK "Plano Balanceado ativado."
        } catch {
            Write-Status ERRO $_.Exception.Message
        }
    }
}

# ============================================================
# ACAO: INSTALL — instala apps via winget (lista separada por virgula)
# ============================================================
function Invoke-ActionInstall {
    param([string]$Apps)

    if (-not $Apps) {
        Write-Status ERRO "Informe os apps com -Apps (ex: 'Git.Git,Microsoft.VSCode')."
        return
    }

    $list = $Apps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($list.Count -eq 0) {
        Write-Status ERRO "Nenhum app valido na lista informada."
        return
    }

    Write-Status INFO "Garantindo que o winget esteja disponivel..."
    try {
        Install-WinUtilWinget
    } catch {
        Write-Status ERRO "Falha ao preparar o winget: $($_.Exception.Message)"
        return
    }

    Write-Status INFO "Instalando: $($list -join ', ')"
    try {
        Install-WinUtilProgramWinget -Action Install -Programs $list
        Write-Status OK "Instalacao concluida."
    } catch {
        Write-Status ERRO $_.Exception.Message
    }
}

# ============================================================
# MENU INTERATIVO
# ============================================================
function Show-Menu {
    Clear-Host
    Write-Host "winutil-cli"
    Write-Host "==========="
    Write-Host "[1] Audit       - Gerar log completo do sistema"
    Write-Host "[2] Tweaks      - Aplicar tweaks (Standard / Minimal / Advanced)"
    Write-Host "[3] Debloat     - Remover apps e APPX desnecessarios"
    Write-Host "[4] DNS         - Trocar DNS"
    Write-Host "[5] Performance - Ativar/desativar Ultimate Performance"
    Write-Host "[6] Install     - Instalar apps via winget ou choco"
    Write-Host "[0] Sair"
    Write-Host ""

    $opt = Read-Host "Selecione uma opcao"

    switch ($opt) {
        '1' { Invoke-ActionAudit }
        '2' {
            $p = Read-Host "Preset (standard / minimal / advanced)"
            if ($p -notin @('standard', 'minimal', 'advanced')) {
                Write-Status ERRO "Preset invalido."
            } else {
                Invoke-ActionTweaks -Preset $p
            }
        }
        '3' { Invoke-ActionDebloat }
        '4' {
            $prov = Read-Host "Provedor de DNS (ex: cloudflare, google, quad9)"
            Invoke-ActionDNS -Provider $prov
        }
        '5' {
            $st = Read-Host "Ultimate Performance (on / off)"
            if ($st -notin @('on', 'off')) {
                Write-Status ERRO "Valor invalido. Use 'on' ou 'off'."
            } else {
                Invoke-ActionPerformance -State $st
            }
        }
        '6' {
            $apps = Read-Host "Apps separados por virgula (ex: Git.Git,Microsoft.VSCode)"
            Invoke-ActionInstall -Apps $apps
        }
        '0' { return }
        default { Write-Status AVISO "Opcao invalida." }
    }
}

# ============================================================
# DISPATCH — parametro vs interativo
# ============================================================
if ($Action) {
    switch ($Action) {
        'audit'       { Invoke-ActionAudit }
        'tweaks'      { Invoke-ActionTweaks -Preset $Preset }
        'debloat'     { Invoke-ActionDebloat }
        'dns'         { Invoke-ActionDNS -Provider $Provider }
        'performance' { Invoke-ActionPerformance -State 'on' }
        'install'     { Invoke-ActionInstall -Apps $Apps }
    }
} else {
    Show-Menu
}