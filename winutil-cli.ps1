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

    # Network: capture interface (e.g. "Ethernet", "1")
    [string]$Interface,

    # Network: capture duration in seconds
    [int]$Duration = 30,

    # Exporter: CLI subaction (install / status / start / stop / metrics / firewall)
    [string]$SubAction,

    # Tweaks: reverts tweaks to their original values
    [switch]$Undo
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
# PRIVILEGES — requires Administrator
# ============================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Status ERRO "This script must be run as Administrator."
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
        Write-Status AVISO "Directory not found: $dir"
        continue
    }
    Get-ChildItem -Path $dir -Filter '*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        } catch {
            Write-Status ERRO "Failed to load $($_.Name): $($_.Exception.Message)"
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
            Write-Status ERRO "Failed to load $($_.Name): $($_.Exception.Message)"
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
            Write-Status AVISO "Invalid JSON in $name.json: $($_.Exception.Message)"
        }
    } else {
        Write-Status AVISO "Config not found: $name.json"
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
    Write-Host "[0] Exit"
    Write-Host ""

    $opt = Read-Host "Select an option"

    switch ($opt) {
        '1' { Invoke-Audit }
        '2' {
            $p = Read-Host "Preset (standard / minimal / advanced)"
            if ($p -notin @('standard', 'minimal', 'advanced')) {
                Write-Status ERRO "Invalid preset."
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
                Write-Status ERRO "Invalid value. Use 'on' or 'off'."
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
        '0' { return }
        default { Write-Status AVISO "Invalid option." }
    }
}

# ============================================================
# DISPATCH — parameter vs interactive
# ============================================================
if ($Action) {
    switch ($Action.ToLower()) {
        'audit'       { Invoke-Audit }
        'tweaks'      { Invoke-Tweaks -Preset $Preset -Undo:$Undo }
        'debloat'     { Invoke-Debloat }
        'dns'         { Invoke-DNS -Provider $Provider -PrimaryDNS $PrimaryDNS -SecondaryDNS $SecondaryDNS }
        'performance' { Invoke-Performance }
        'install'     { Invoke-Install -Apps $Apps }
        'memory'      { Invoke-Memory }
        'network'     { Invoke-Network -Interface $Interface -Duration $Duration }
        'exporter'    { Invoke-Exporter -SubAction $SubAction }
        default       { Write-Status ERRO "Unknown action: $Action" }
    }
} else {
    Show-Menu
}
