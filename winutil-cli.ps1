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
    .\winutil-cli.ps1 -Action dns -Provider custom -PrimaryDNS 192.168.15.173 -SecondaryDNS 9.9.9.9
    .\winutil-cli.ps1 -Action debloat
    .\winutil-cli.ps1 -Action performance
    .\winutil-cli.ps1 -Action install -Apps "Git.Git,Microsoft.VSCode"
    .\winutil-cli.ps1 -Action memory
    .\winutil-cli.ps1 -Action network
    .\winutil-cli.ps1 -Action network -Interface "Ethernet" -Duration 60
    .\winutil-cli.ps1 -Action exporter
    .\winutil-cli.ps1 -Action exporter -SubAction install
    .\winutil-cli.ps1 -Action exporter -SubAction status
    .\winutil-cli.ps1 -Action exporter -SubAction metrics
#>

[CmdletBinding()]
param(
    [ValidateSet('audit', 'tweaks', 'debloat', 'dns', 'performance', 'install', 'memory', 'network', 'exporter')]
    [string]$Action,

    [ValidateSet('standard', 'minimal', 'advanced')]
    [string]$Preset = 'standard',

    [string]$Provider,

    [string]$PrimaryDNS,

    [string]$SecondaryDNS,

    [string]$Apps,

    # Network: interface de captura (ex: "Ethernet", "1")
    [string]$Interface,

    # Network: duracao da captura em segundos
    [int]$Duration = 30,

    # Exporter: subacao CLI (install / status / start / stop / metrics / firewall)
    [string]$SubAction
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
        'Microsoft.BingNews'
        'Microsoft.BingWeather'
        'Microsoft.BingSearch'
        'Microsoft.GamingApp'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Todos'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.XboxApp'
        'Microsoft.XboxGameOverlay'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxIdentityProvider'
        'Microsoft.XboxSpeechToTextOverlay'
        'Microsoft.YourPhone'
        'Microsoft.ZuneMusic'
        'Microsoft.ZuneVideo'
        'Clipchamp.Clipchamp'
        'MicrosoftTeams'
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
# ACAO: DNS — troca o DNS via Set-WinUtilDNS (le do dns.json).
# Provider 'custom' usa os IPs informados (-PrimaryDNS / -SecondaryDNS).
# ============================================================
function Invoke-ActionDNS {
    param(
        [string]$Provider,
        [string]$PrimaryDNS,
        [string]$SecondaryDNS
    )

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

    $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $hiPerfGuid   = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

    if ($State -eq 'on') {
        Write-Status INFO "Detectando plano de alto desempenho disponivel..."

        $planOutput = powercfg /list 2>&1
        $targetGuid = $null

        # Prioridade 1: GUID original do Ultimate Performance ja presente
        if ($planOutput -match [regex]::Escape($ultimateGuid)) {
            $targetGuid = $ultimateGuid
        }

        # Prioridade 2: qualquer plano com "Ultimate" ou "Desempenho Maximo" no nome
        if (-not $targetGuid) {
            foreach ($line in $planOutput) {
                if ($line -match 'Ultimate|Desempenho M.ximo') {
                    if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $targetGuid = $Matches[1]
                        break
                    }
                }
            }
        }

        # Tenta adicionar o plano original via duplicatescheme (funciona em Pro/Enterprise)
        if (-not $targetGuid) {
            Write-Status INFO "Tentando adicionar Ultimate Performance via duplicatescheme..."
            powercfg -duplicatescheme $ultimateGuid 2>&1 | Out-Null
            $planOutput = powercfg /list 2>&1
            if ($planOutput -match [regex]::Escape($ultimateGuid)) {
                $targetGuid = $ultimateGuid
            }
        }

        # Prioridade 3: Alto desempenho (8c5e7fda)
        if (-not $targetGuid) {
            if ($planOutput -match [regex]::Escape($hiPerfGuid)) {
                $targetGuid = $hiPerfGuid
            }
        }

        # Prioridade 4: fallback Balanceado
        if (-not $targetGuid) {
            Write-Status AVISO "Nenhum plano de alto desempenho encontrado. Usando Balanceado."
            $targetGuid = $balancedGuid
        }

        Write-Status INFO "Ativando: $targetGuid"
        try {
            powercfg -setactive $targetGuid
            Write-Status OK "Plano de energia ativado."
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
# ACAO: MEMORY — limpa a RAM via WinMemoryCleaner.exe
# Baixa o executavel na primeira execucao, se ainda nao existir.
# ============================================================
function Invoke-ActionMemory {
    $toolsDir = Join-Path $root 'tools'
    $exePath  = Join-Path $toolsDir 'WinMemoryCleaner.exe'
    $url      = 'https://github.com/IgorMundstein/WinMemoryCleaner/releases/download/3.0.8/WinMemoryCleaner.exe'

    # Garante o executavel
    if (-not (Test-Path $exePath)) {
        Write-Status INFO "WinMemoryCleaner.exe nao encontrado. Baixando..."
        try {
            if (-not (Test-Path $toolsDir)) {
                New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
            }
            # TLS 1.2 para o download funcionar no PS 5.1
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $exePath -UseBasicParsing
            Write-Status OK "Download concluido."
        } catch {
            Write-Status ERRO "Falha no download: $($_.Exception.Message)"
            return
        }
    }

    # RAM livre antes
    $ramAntes = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    Write-Status INFO "RAM livre antes: $ramAntes GB"

    # Limpeza silenciosa (sem GUI)
    Write-Status INFO "Limpando memoria..."
    try {
        $cleanerArgs = '/CombinedPageList', '/ModifiedPageList', '/ProcessesWorkingSet', '/StandbyList', '/SystemWorkingSet'
        Start-Process -FilePath $exePath -ArgumentList $cleanerArgs -Wait -NoNewWindow
        Write-Status OK "Limpeza concluida."
    } catch {
        Write-Status ERRO "Falha ao executar: $($_.Exception.Message)"
        return
    }

    # RAM livre depois
    $ramDepois = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    Write-Status INFO "RAM livre depois: $ramDepois GB"
}

# ============================================================
# ACAO: NETWORK — captura de pacotes com TShark e relatorio
# ============================================================
function Invoke-ActionNetwork {
    param(
        [string]$Interface,
        [int]$Duration = 30
    )

    # Localiza o executavel do tshark
    $tsharkCmd = $null
    $candidatos = @('tshark', 'C:\Program Files\Wireshark\tshark.exe')
    foreach ($c in $candidatos) {
        try {
            $null = & $c --version 2>&1
            if ($LASTEXITCODE -eq 0) { $tsharkCmd = $c; break }
        } catch {}
    }

    # Instala Wireshark via winget se necessario
    if (-not $tsharkCmd) {
        Write-Status AVISO "TShark nao encontrado. Instalando Wireshark via winget..."
        try {
            winget install WiresharkFoundation.Wireshark --silent --accept-package-agreements
            Write-Status OK "Wireshark instalado."
            # Atualiza PATH sem reiniciar o processo
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        } catch {
            Write-Status ERRO "Falha ao instalar Wireshark: $($_.Exception.Message)"
            return
        }
        $tsharkCmd = 'C:\Program Files\Wireshark\tshark.exe'
        if (-not (Test-Path $tsharkCmd)) {
            Write-Status ERRO "tshark nao localizado apos instalacao. Reinicie o terminal."
            return
        }
    }

    # Lista interfaces disponiveis
    Write-Status INFO "Interfaces de rede disponiveis:"
    try {
        & $tsharkCmd -D 2>&1 | ForEach-Object { Write-Host "  $_" }
    } catch {
        Write-Status ERRO "Falha ao listar interfaces: $($_.Exception.Message)"
        return
    }

    # Define interface (interativo ou parametro)
    if (-not $Interface) {
        $Interface = Read-Host "Informe o nome ou numero da interface para captura"
    }
    if (-not $Interface) {
        Write-Status ERRO "Nenhuma interface informada. Abortando."
        return
    }

    # Garante pastas de saida
    $capturesDir = 'C:\WinUtil\Captures'
    $reportsDir  = 'C:\WinUtil\Reports'
    foreach ($d in @($capturesDir, $reportsDir)) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # Nomes com timestamp
    $ts       = Get-Date -Format 'dd.MM.yyyy_HH.mm.ss'
    $pcapFile = Join-Path $capturesDir "$ts.pcapng"
    $rptFile  = Join-Path $reportsDir  "$ts.txt"

    # Captura de pacotes
    Write-Status INFO "Capturando por $Duration segundo(s) na interface '$Interface'..."
    Write-Status INFO "Destino: $pcapFile"
    try {
        & $tsharkCmd -i $Interface -a "duration:$Duration" -w $pcapFile 2>&1 | Out-Null
        if (-not (Test-Path $pcapFile)) {
            Write-Status ERRO "Arquivo de captura nao gerado. Verifique interface e permissoes."
            return
        }
        Write-Status OK "Captura concluida."
    } catch {
        Write-Status ERRO "Falha na captura: $($_.Exception.Message)"
        return
    }

    # Gera relatorio em TXT
    Write-Status INFO "Gerando relatorio..."
    try {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("=== WinUtil-CLI Network Report ===")
        [void]$sb.AppendLine("Captura  : $pcapFile")
        [void]$sb.AppendLine("Data     : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
        [void]$sb.AppendLine("Interface: $Interface")
        [void]$sb.AppendLine("Duracao  : $Duration segundo(s)")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("--- Estatisticas Gerais ---")
        $stats = & $tsharkCmd -r $pcapFile -qz io,stat,0 2>&1
        [void]$sb.AppendLine(($stats -join [Environment]::NewLine))
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("--- Top 15 IPs de Destino ---")
        $ips = & $tsharkCmd -r $pcapFile -T fields -e ip.dst 2>&1 |
               Where-Object { $_ -match '^\d{1,3}\.' }
        if ($ips) {
            $ips | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
            ForEach-Object { [void]$sb.AppendLine("  $($_.Count.ToString().PadLeft(6))  $($_.Name)") }
        } else {
            [void]$sb.AppendLine("  (nenhum IP capturado)")
        }
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("--- Conversas TCP ---")
        $conv = & $tsharkCmd -r $pcapFile -qz conv,tcp 2>&1
        [void]$sb.AppendLine(($conv -join [Environment]::NewLine))
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("--- Top Protocolos ---")
        $phs = & $tsharkCmd -r $pcapFile -qz io,phs 2>&1
        [void]$sb.AppendLine(($phs -join [Environment]::NewLine))

        $sb.ToString() | Set-Content -Path $rptFile -Encoding UTF8
        Write-Status OK "Relatorio: $rptFile"
    } catch {
        Write-Status ERRO "Falha ao gerar relatorio: $($_.Exception.Message)"
    }

    # Resumo final no terminal
    Write-Host ""
    Write-Host "=== Resumo ===" -ForegroundColor Cyan
    Write-Host "  Captura  : $pcapFile" -ForegroundColor White
    Write-Host "  Relatorio: $rptFile"  -ForegroundColor White
}

# ============================================================
# ACAO: EXPORTER — instala e gerencia windows_exporter (Prometheus)
# Usa Start-Process em vez de servico Windows (falha com "Funcao incorreta" no Win11)
# ============================================================
function Invoke-ActionExporter {
    param([string]$SubAction)

    $exePath  = 'C:\Program Files\windows_exporter\windows_exporter.exe'
    $taskName = 'windows_exporter'

    # Inicia o processo se nao estiver rodando
    function Start-ExporterProcess {
        $proc = Get-Process -Name 'windows_exporter' -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Status INFO "windows_exporter ja esta rodando (PID: $($proc.Id))."
            return
        }
        if (-not (Test-Path $exePath)) {
            Write-Status ERRO "Executavel nao encontrado: $exePath. Execute a subacao 'install'."
            return
        }
        try {
            Start-Process -FilePath $exePath -WindowStyle Hidden
            Write-Status OK "windows_exporter iniciado via Start-Process."
        } catch {
            Write-Status ERRO "Falha ao iniciar processo: $($_.Exception.Message)"
        }
    }

    # Registra tarefa agendada para subir no boot como SYSTEM
    function Register-ExporterTask {
        try {
            $action    = New-ScheduledTaskAction -Execute $exePath
            $trigger   = New-ScheduledTaskTrigger -AtStartup
            $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                -Settings $settings -Principal $principal -Force | Out-Null
            Write-Status OK "Tarefa agendada '$taskName' registrada (boot/SYSTEM)."
        } catch {
            Write-Status ERRO "Falha ao registrar tarefa agendada: $($_.Exception.Message)"
        }
    }

    function Install-WindowsExporter {
        # Verifica se executavel ja existe
        if (Test-Path $exePath) {
            Write-Status INFO "windows_exporter ja instalado em: $exePath"
            Start-ExporterProcess
            Register-ExporterTask
            Show-ExporterMetrics
            Set-ExporterFirewall
            return
        }

        $winUtilDir = 'C:\WinUtil'
        $msiPath    = Join-Path $winUtilDir 'windows_exporter.msi'
        if (-not (Test-Path $winUtilDir)) {
            New-Item -ItemType Directory -Path $winUtilDir -Force | Out-Null
        }

        # Obtem URL do MSI mais recente via GitHub API
        Write-Status INFO "Consultando release mais recente do windows_exporter..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $apiUrl  = 'https://api.github.com/repos/prometheus-community/windows_exporter/releases/latest'
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            $asset   = $release.assets |
                       Where-Object { $_.name -match 'amd64\.msi$' } |
                       Select-Object -First 1
            if (-not $asset) {
                Write-Status ERRO "MSI amd64 nao encontrado no release mais recente."
                return
            }
            Write-Status INFO "Versao: $($release.tag_name) / $($asset.name)"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing
            Write-Status OK "Download concluido: $msiPath"
        } catch {
            Write-Status ERRO "Falha no download: $($_.Exception.Message)"
            return
        }

        # Instalacao silenciosa com coletores essenciais
        Write-Status INFO "Instalando windows_exporter..."
        try {
            $collectors = 'cpu,cs,logical_disk,net,os,process,service,hyperv'
            $install = Start-Process msiexec `
                -ArgumentList "/i `"$msiPath`" /quiet ENABLED_COLLECTORS=`"$collectors`"" `
                -Wait -PassThru
            if ($install.ExitCode -ne 0) {
                Write-Status ERRO "msiexec encerrou com codigo $($install.ExitCode)."
                return
            }
            Write-Status OK "windows_exporter instalado."
        } catch {
            Write-Status ERRO "Falha na instalacao: $($_.Exception.Message)"
            return
        }

        Start-ExporterProcess
        Register-ExporterTask
        Show-ExporterMetrics
        Set-ExporterFirewall
    }

    function Stop-ExporterProcess {
        $proc = Get-Process -Name 'windows_exporter' -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Status AVISO "windows_exporter nao esta rodando."
            return
        }
        try {
            Stop-Process -Name 'windows_exporter' -Force
            Write-Status OK "windows_exporter encerrado."
        } catch {
            Write-Status ERRO "Falha ao encerrar processo: $($_.Exception.Message)"
        }
    }

    function Show-ExporterStatus {
        $proc = Get-Process -Name 'windows_exporter' -ErrorAction SilentlyContinue
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($proc) {
            Write-Status OK    "Processo       : Rodando (PID: $($proc.Id))"
        } else {
            Write-Status AVISO "Processo       : Parado"
        }

        if ($task) {
            Write-Status INFO "Tarefa agendada: $($task.TaskName) / Estado: $($task.State)"
        } else {
            Write-Status AVISO "Tarefa agendada: Nao encontrada. Execute 'install' para registrar."
        }
    }

    function Show-ExporterMetrics {
        $hostname = $env:COMPUTERNAME
        $url      = "http://${hostname}:9182/metrics"
        Write-Status INFO "URL de metricas: $url"
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            Write-Status OK "Porta 9182 acessivel (HTTP $($resp.StatusCode))."
        } catch {
            Write-Status AVISO "Porta 9182 nao respondeu: $($_.Exception.Message)"
        }
    }

    function Set-ExporterFirewall {
        $ruleName = 'WinUtil - windows_exporter 9182'
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Status INFO "Regra de firewall ja existe: '$ruleName'."
            return
        }
        try {
            New-NetFirewallRule `
                -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 9182 `
                -Action Allow `
                -Profile Any | Out-Null
            Write-Status OK "Regra de firewall criada: '$ruleName'."
        } catch {
            Write-Status ERRO "Falha ao criar regra de firewall: $($_.Exception.Message)"
        }
    }

    # Dispatch CLI via -SubAction
    if ($SubAction) {
        switch ($SubAction.ToLower()) {
            'install'  { Install-WindowsExporter }
            'status'   { Show-ExporterStatus }
            'start'    { Start-ExporterProcess }
            'stop'     { Stop-ExporterProcess }
            'metrics'  { Show-ExporterMetrics }
            'firewall' { Set-ExporterFirewall }
            default    {
                Write-Status ERRO "SubAction desconhecida: '$SubAction'."
                Write-Status INFO "Opcoes: install, status, start, stop, metrics, firewall"
            }
        }
        return
    }

    # Menu interativo do modulo Exporter
    while ($true) {
        Write-Host ""
        Write-Host "[9] Exporter - windows_exporter para Prometheus" -ForegroundColor Cyan
        Write-Host "  [1] Instalar/verificar windows_exporter"
        Write-Host "  [2] Ver status do processo"
        Write-Host "  [3] Iniciar processo"
        Write-Host "  [4] Parar processo"
        Write-Host "  [5] Ver URL de metricas"
        Write-Host "  [6] Abrir firewall porta 9182"
        Write-Host "  [0] Voltar"
        Write-Host ""
        $sub = Read-Host "Selecione"
        switch ($sub) {
            '1' { Install-WindowsExporter }
            '2' { Show-ExporterStatus }
            '3' { Start-ExporterProcess }
            '4' { Stop-ExporterProcess }
            '5' { Show-ExporterMetrics }
            '6' { Set-ExporterFirewall }
            '0' { return }
            default { Write-Status AVISO "Opcao invalida." }
        }
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
    Write-Host "[7] Memory      - Limpar memoria RAM"
    Write-Host "[8] Network     - Captura de pacotes com TShark"
    Write-Host "[9] Exporter    - Instalar/gerenciar windows_exporter (Prometheus)"
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
            $prov = Read-Host "Provedor de DNS (ex: cloudflare, google, quad9, custom)"
            if ($prov -eq 'custom') {
                $p1 = Read-Host "DNS primario (ex: 192.168.15.173)"
                $p2 = Read-Host "DNS secundario (opcional)"
                Invoke-ActionDNS -Provider 'custom' -PrimaryDNS $p1 -SecondaryDNS $p2
            } else {
                Invoke-ActionDNS -Provider $prov
            }
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
        '7' { Invoke-ActionMemory }
        '8' {
            $iface = Read-Host "Interface de captura (nome ou numero; Enter para listar e escolher)"
            $dur   = Read-Host "Duracao em segundos (Enter = 30)"
            $d     = if ($dur -match '^\d+$') { [int]$dur } else { 30 }
            Invoke-ActionNetwork -Interface $iface -Duration $d
        }
        '9' { Invoke-ActionExporter }
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
        'dns'         { Invoke-ActionDNS -Provider $Provider -PrimaryDNS $PrimaryDNS -SecondaryDNS $SecondaryDNS }
        'performance' { Invoke-ActionPerformance -State 'on' }
        'install'     { Invoke-ActionInstall -Apps $Apps }
        'memory'      { Invoke-ActionMemory }
        'network'     { Invoke-ActionNetwork -Interface $Interface -Duration $Duration }
        'exporter'    { Invoke-ActionExporter -SubAction $SubAction }
        default       { Write-Status ERRO "Acao desconhecida: $Action" }
    }
} else {
    Show-Menu
}