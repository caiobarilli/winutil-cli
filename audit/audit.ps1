# audit.ps1 - Auditoria do Desktop Windows
# Salvar em C:\audit.ps1 e executar como Administrador

$date = Get-Date -Format "dd.MM.yyyy"
$time = Get-Date -Format "HH:mm:ss"
$logDir = "C:\log\$date"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# Encoding UTF-8 sem BOM (compativel com PS 5.1 e 7+)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Block {
    param($file, $title, $content)
    $header = @"
================================================================================
$title
Gerado em: $date $time
================================================================================

"@
    [System.IO.File]::WriteAllText("$logDir\$file", ($header + $content), $utf8NoBom)
    Write-Host "[ OK ] $file"
}

# ============================================================
# CHECAGEM DE PRIVILEGIOS
# ============================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ AVISO ] Sem privilegios de Administrador." -ForegroundColor Yellow
    Write-Host "          Blocos de rede e tarefas podem vir incompletos." -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
# BLOCO 01 - SISTEMA
# ============================================================
$os       = Get-CimInstance Win32_OperatingSystem
$cs       = Get-CimInstance Win32_ComputerSystem
$uptime   = (Get-Date) - $os.LastBootUpTime
$content  = @"
Hostname        : $($cs.Name)
Dominio         : $($cs.Domain)
Usuario         : $($env:USERNAME)
Sistema         : $($os.Caption)
Versao          : $($os.Version)
Build           : $($os.BuildNumber)
Arquitetura     : $($os.OSArchitecture)
Uptime          : $([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m $($uptime.Seconds)s
Ultimo Boot     : $($os.LastBootUpTime)
Fuso Horario    : $((Get-TimeZone).DisplayName)
"@
Write-Block "01-sistema.txt" "BLOCO 01 - SISTEMA" $content

# ============================================================
# BLOCO 02 - HARDWARE
# ============================================================
$cpu     = Get-CimInstance Win32_Processor | Select-Object -First 1
$ram     = Get-CimInstance Win32_OperatingSystem
$ramTotal = [math]::Round($ram.TotalVisibleMemorySize / 1MB, 2)
$ramFree  = [math]::Round($ram.FreePhysicalMemory / 1MB, 2)
$ramUsed  = [math]::Round($ramTotal - $ramFree, 2)
$gpu      = Get-CimInstance Win32_VideoController | Select-Object -First 1

# VRAM via registro (AdapterRAM satura em ~4GB por ser uint32)
$vramGB = "N/D"
try {
    $videoKey = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^\d{4}$' } |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.'HardwareInformation.qwMemorySize' } |
        Select-Object -First 1
    if ($videoKey) {
        $vramGB = "$([math]::Round($videoKey.'HardwareInformation.qwMemorySize' / 1GB, 1)) GB"
    }
} catch { }

$discos = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
    $total = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
    $used  = [math]::Round($_.Used / 1GB, 1)
    $free  = [math]::Round($_.Free / 1GB, 1)
    "  $($_.Name):\ | Total: ${total}GB | Usado: ${used}GB | Livre: ${free}GB"
}

$content = @"
CPU
  Nome        : $($cpu.Name)
  Nucleos     : $($cpu.NumberOfCores)
  Threads     : $($cpu.NumberOfLogicalProcessors)
  Clock Max   : $($cpu.MaxClockSpeed) MHz

GPU
  Nome        : $($gpu.Name)
  VRAM        : $vramGB

RAM
  Total       : ${ramTotal} GB
  Usada       : ${ramUsed} GB
  Livre       : ${ramFree} GB

DISCOS
$($discos -join "`n")
"@
Write-Block "02-hardware.txt" "BLOCO 02 - HARDWARE" $content

# ============================================================
# BLOCO 03 - PROCESSOS
# ============================================================
$procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 30 |
    ForEach-Object {
        "{0,-40} CPU: {1,8}   RAM: {2,8} MB" -f $_.Name, [math]::Round($_.CPU,2), [math]::Round($_.WorkingSet64/1MB,1)
    }

$content = $procs -join "`n"
Write-Block "03-processos.txt" "BLOCO 03 - PROCESSOS (Top 30 por RAM)" $content

# ============================================================
# BLOCO 04 - SERVICOS
# ============================================================
$svcs = Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object DisplayName |
    ForEach-Object {
        "{0,-50} {1,-10} {2}" -f $_.DisplayName, $_.Status, $_.StartType
    }

$content = $svcs -join "`n"
Write-Block "04-servicos.txt" "BLOCO 04 - SERVICOS RODANDO" $content

# ============================================================
# BLOCO 05 - STARTUP
# ============================================================
$startup = Get-CimInstance Win32_StartupCommand | Sort-Object Name |
    ForEach-Object {
        "{0,-45} {1}" -f $_.Name, $_.Command
    }

$content = $startup -join "`n"
Write-Block "05-startup.txt" "BLOCO 05 - PROGRAMAS NA INICIALIZACAO" $content

# ============================================================
# BLOCO 06 - REDE
# ============================================================
# Puxa as conexoes uma vez e cacheia os processos por Id
$tcp = Get-NetTCPConnection
$procCache = @{}
Get-Process | ForEach-Object { $procCache[$_.Id] = $_.Name }

function Resolve-ProcName($processId) {
    if ($procCache.ContainsKey([int]$processId)) { $procCache[[int]$processId] } else { "unknown" }
}

$conns = $tcp | Where-Object { $_.State -eq "Established" } |
    ForEach-Object {
        $proc = Resolve-ProcName $_.OwningProcess
        "{0,-25} {1,-22} {2,-22} {3}" -f $proc, "$($_.LocalAddress):$($_.LocalPort)", "$($_.RemoteAddress):$($_.RemotePort)", $_.State
    }

$ports = $tcp | Where-Object { $_.State -eq "Listen" } |
    ForEach-Object {
        $proc = Resolve-ProcName $_.OwningProcess
        "{0,-25} {1}" -f $proc, "$($_.LocalAddress):$($_.LocalPort)"
    }

$content = @"
CONEXOES ESTABELECIDAS
$($conns -join "`n")

PORTAS ABERTAS (LISTEN)
$($ports -join "`n")
"@
Write-Block "06-rede.txt" "BLOCO 06 - REDE" $content

# ============================================================
# BLOCO 07 - TAREFAS AGENDADAS
# ============================================================
$tasks = Get-ScheduledTask | Where-Object { $_.State -eq "Ready" -or $_.State -eq "Running" } |
    Sort-Object TaskName |
    ForEach-Object {
        "{0,-50} {1,-10} {2}" -f $_.TaskName, $_.State, $_.TaskPath
    }

$content = $tasks -join "`n"
Write-Block "07-tarefas.txt" "BLOCO 07 - TAREFAS AGENDADAS (Ativas)" $content

# ============================================================
# BLOCO 08 - HYPER-V
# ============================================================
if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
    try {
        $vms = Get-VM -ErrorAction Stop | ForEach-Object {
            $mem = [math]::Round($_.MemoryAssigned / 1MB, 0)
            "{0,-25} {1,-12} CPU: {2,5}%   RAM: {3} MB   Uptime: {4}" -f $_.Name, $_.State, $_.CPUUsage, $mem, $_.Uptime
        }
        $content = if ($vms) { $vms -join "`n" } else { "Nenhuma VM encontrada." }
    } catch {
        $content = "Erro ao consultar VMs: $($_.Exception.Message)"
    }
} else {
    $content = "Modulo Hyper-V nao disponivel nesta maquina."
}
Write-Block "08-hyperv.txt" "BLOCO 08 - HYPER-V VMs" $content

# ============================================================
# FIM
# ============================================================
Write-Host ""
Write-Host "Auditoria concluida: $logDir"