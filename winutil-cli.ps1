#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point for winutil-cli — a CLI fork of WinUtil (ChrisTitusTech), without GUI/WPF.

.DESCRIPTION
    Runs locally or via SSH, on PowerShell 5.1 or 7+.
    Two modes:
      - Interactive: no parameters, displays a numbered menu.
      - Parameter  : via -Action for CLI/SSH use.

.EXAMPLE
    .\winutil-cli.ps1
    .\winutil-cli.ps1 -Action audit
    .\winutil-cli.ps1 -Action tweaks -Preset standard
    .\winutil-cli.ps1 -Action tweaks -Preset standard -Undo
    .\winutil-cli.ps1 -Action dns -Provider cloudflare
    .\winutil-cli.ps1 -Action dns -Provider custom -PrimaryDNS <PRIMARY_IP> -SecondaryDNS <SECONDARY_IP>
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
    .\winutil-cli.ps1 -Action optimize -Preset ssh
    .\winutil-cli.ps1 -Action optimize -Kill "notepad,calc"
    .\winutil-cli.ps1 -Action optimize -Preset ssh -Kill "notepad,calc"
    .\winutil-cli.ps1 -Action optimize -Preset ssh -Undo
#>

[CmdletBinding()]
param(
    [ValidateSet('audit', 'tweaks', 'debloat', 'dns', 'performance', 'install', 'memory', 'network', 'exporter', 'processes', 'optimize')]
    [string]$Action,

    [ValidateSet('standard', 'minimal', 'advanced', 'ssh', 'kill-rdp')]
    [string]$Preset,

    [string]$Provider,

    [string]$PrimaryDNS,

    [string]$SecondaryDNS,

    [string]$Apps,

    # Network: capture interface (e.g. "Ethernet", "1")
    [string]$Interface,

    # Network: capture duration in seconds
    [int]$Duration = 30,

    # Exporter: CLI subaction (install / status / start / stop / metrics / firewall)
    [string]$SubAction,

    # Tweaks/Optimize: reverts to original state
    [switch]$Undo,

    # Optimize: comma-separated list of process names to stop
    [string]$Kill
)

# ============================================================
# ENCODING — UTF-8 without BOM (works on PS 5.1 and 7+)
# ============================================================
$OutputEncoding             = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding    = [System.Text.UTF8Encoding]::new($false)

# ============================================================
# STATUS — standardized terminal messages
# ============================================================
function Write-Status {
    param(
        [ValidateSet('OK', 'ERROR', 'WARNING', 'INFO')]
        [string]$Level,
        [string]$Message
    )
    $map = @{
        OK      = @{ Tag = '[ OK ]';      Color = 'Green'  }
        ERROR   = @{ Tag = '[ ERROR ]';   Color = 'Red'    }
        WARNING = @{ Tag = '[ WARNING ]'; Color = 'Yellow' }
        INFO    = @{ Tag = '[ INFO ]';    Color = 'Gray'   }
    }
    Write-Host "$($map[$Level].Tag) $Message" -ForegroundColor $map[$Level].Color
}

# ============================================================
# PRIVILEGES — requires Administrator
# ============================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Status ERROR "This script must be run as Administrator."
    Write-Status INFO "Open the terminal with 'Run as administrator' and try again."
    exit 1
}

# ============================================================
# FUNCTION LOADING — dot-source from private/, public/ and scripts/
# ============================================================
$root = $PSScriptRoot

$funcDirs = @(
    (Join-Path $root 'functions\private'),
    (Join-Path $root 'functions\public')
)

foreach ($dir in $funcDirs) {
    if (-not (Test-Path $dir)) {
        Write-Status WARNING "Directory not found: $dir"
        continue
    }
    Get-ChildItem -Path $dir -Filter '*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        } catch {
            Write-Status ERROR "Failed to load $($_.Name): $($_.Exception.Message)"
        }
    }
}

$scriptsDir = Join-Path $root 'scripts'
if (Test-Path $scriptsDir) {
    # Load only Invoke-* modules — avoids upstream GUI files
    Get-ChildItem -Path $scriptsDir -Filter 'Invoke-*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        } catch {
            Write-Status ERROR "Failed to load $($_.Name): $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CONFIGS — builds the global $sync hashtable used by functions
# Project functions read from $sync.configs.<name> (e.g. $sync.configs.dns)
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
            Write-Status WARNING "Invalid JSON in $name.json: $($_.Exception.Message)"
        }
    } else {
        Write-Status WARNING "Config not found: $name.json"
    }
}

# ============================================================
# INTERACTIVE MENU
# ============================================================
function Show-Menu {
    Clear-Host
    Write-Host "winutil-cli"
    Write-Host "==========="
    Write-Host "[1] Audit       - Generate complete system log"
    Write-Host "[2] Tweaks      - Apply tweaks (Standard / Minimal / Advanced)"
    Write-Host "[3] Debloat     - Remove unnecessary apps and APPX packages"
    Write-Host "[4] DNS         - Change DNS"
    Write-Host "[5] Performance - Enable/disable Ultimate Performance"
    Write-Host "[6] Install     - Install apps via winget or choco"
    Write-Host "[7] Memory      - Clean RAM memory"
    Write-Host "[8] Network     - Packet capture with TShark"
    Write-Host "[9] Exporter    - Install/manage windows_exporter (Prometheus)"
    Write-Host "[10] Processes  - Show top 30 processes by RAM"
    Write-Host "[11] Optimize   - Stop processes (preset: ssh, or custom kill list)"
    Write-Host "[0] Exit"
    Write-Host ""

    $opt = Read-Host "Select an option"

    switch ($opt) {
        '1' { Invoke-Audit }
        '2' {
            $p = Read-Host "Preset (standard / minimal / advanced)"
            if ($p -notin @('standard', 'minimal', 'advanced')) {
                Write-Status ERROR "Invalid preset."
            } else {
                $undoResp = Read-Host "Undo? (y/n, Enter = n)"
                if ($undoResp -eq 'y') {
                    Invoke-Tweaks -Preset $p -Undo
                } else {
                    Invoke-Tweaks -Preset $p
                }
            }
        }
        '3' { Invoke-Debloat }
        '4' {
            $prov = Read-Host "DNS provider (e.g.: cloudflare, google, quad9, custom)"
            if ($prov -eq 'custom') {
                $p1 = Read-Host "Primary DNS"
                $p2 = Read-Host "Secondary DNS (optional)"
                Invoke-DNS -Provider 'custom' -PrimaryDNS $p1 -SecondaryDNS $p2
            } else {
                Invoke-DNS -Provider $prov
            }
        }
        '5' {
            $st = Read-Host "Ultimate Performance (on / off)"
            if ($st -notin @('on', 'off')) {
                Write-Status ERROR "Invalid value. Use 'on' or 'off'."
            } else {
                Invoke-Performance -State $st
            }
        }
        '6' {
            $apps = Read-Host "Apps separated by comma (e.g.: Git.Git,Microsoft.VSCode)"
            Invoke-Install -Apps $apps
        }
        '7' { Invoke-Memory }
        '8' {
            $iface = Read-Host "Capture interface (name or number; Enter to list and choose)"
            $dur   = Read-Host "Duration in seconds (Enter = 30)"
            $d     = if ($dur -match '^\d+$') { [int]$dur } else { 30 }
            Invoke-Network -Interface $iface -Duration $d
        }
        '9' { Invoke-Exporter }
        '10' { Invoke-Processes }
        '11' {
            $p = Read-Host "Preset (ssh / Enter to skip)"
            $k = Read-Host "Kill list (comma-separated, Enter to skip)"
            $undoResp = Read-Host "Undo? (y/n, Enter = n)"
            if ($undoResp -eq 'y') {
                Invoke-Optimize -Preset $p -Kill $k -Undo
            } else {
                Invoke-Optimize -Preset $p -Kill $k
            }
        }
        '0' { return }
        default { Write-Status WARNING "Invalid option." }
    }
}

# ============================================================
# DISPATCH — parameter vs interactive
# ============================================================
if ($Action) {
    switch ($Action.ToLower()) {
        'audit'       { Invoke-Audit }
        'tweaks'      { Invoke-Tweaks -Preset $(if ($Preset) { $Preset } else { 'standard' }) -Undo:$Undo }
        'debloat'     { Invoke-Debloat }
        'dns'         { Invoke-DNS -Provider $Provider -PrimaryDNS $PrimaryDNS -SecondaryDNS $SecondaryDNS }
        'performance' { Invoke-Performance }
        'install'     { Invoke-Install -Apps $Apps }
        'memory'      { Invoke-Memory }
        'network'     { Invoke-Network -Interface $Interface -Duration $Duration }
        'exporter'    { Invoke-Exporter -SubAction $SubAction }
        'processes'   { Invoke-Processes }
        'optimize'    { Invoke-Optimize -Preset $Preset -Kill $Kill -Undo:$Undo }
        default       { Write-Status ERROR "Unknown action: $Action" }
    }
} else {
    Show-Menu
}
