function Invoke-Optimize {
    param(
        [string]$Preset,
        [string]$Kill,
        [switch]$Undo
    )

    $stateFile = 'C:\WinUtil\optimize-state.json'
    $stateDir  = 'C:\WinUtil'

    $sshProcesses = @(
        'LogonUI', 'SearchHost', 'StartMenuExperienceHost',
        'ShellExperienceHost', 'ShellHost', 'TextInputHost',
        'msedgewebview2', 'OfficeClickToRun'
    )

    $killRdpProcesses = @(
        'explorer', 'SearchHost', 'StartMenuExperienceHost',
        'ShellExperienceHost', 'ShellHost', 'TextInputHost',
        'msedgewebview2', 'dwm', 'sihost', 'RuntimeBroker',
        'backgroundTaskHost', 'CrossDeviceResume'
    )

    # Service-backed processes: disable before stopping to prevent SCM auto-restart.
    # Entries absent from this map fall back to Stop-Process.
    $serviceMap = @{
        'SearchHost'       = 'WSearch'
        'TextInputHost'    = 'TextInputManagementService'
        'OfficeClickToRun' = 'ClickToRunSvc'
    }

    # ── UNDO ─────────────────────────────────────────────────────────────────
    if ($Undo) {
        if (-not (Test-Path $stateFile)) {
            Write-Status ERROR "State file not found: $stateFile. Nothing to undo."
            return
        }
        $raw   = Get-Content -Path $stateFile -Raw
        $state = $raw | ConvertFrom-Json
        foreach ($prop in $state.PSObject.Properties) {
            $svcName  = $prop.Name
            $origType = $prop.Value
            Set-Service  -Name $svcName -StartupType $origType -ErrorAction SilentlyContinue
            Start-Service -Name $svcName -ErrorAction SilentlyContinue
            Write-Status OK "Restored: $svcName"
        }
        Remove-Item -Path $stateFile -Force -ErrorAction SilentlyContinue
        Write-Status OK "Optimize undo complete."
        return
    }

    # ── APPLY ─────────────────────────────────────────────────────────────────
    $targets = [System.Collections.Generic.List[string]]::new()

    if ($Preset) {
        switch ($Preset.ToLower()) {
            'ssh' {
                Write-Status INFO "Preset 'ssh': stopping headless-incompatible processes..."
                foreach ($p in $sshProcesses) { $targets.Add($p) }
            }
            'kill-rdp' {
                Write-Status INFO "Preset 'kill-rdp': stopping RDP session remnants..."
                foreach ($p in $killRdpProcesses) { $targets.Add($p) }
            }
            default {
                Write-Status ERROR "Unknown preset '$Preset'. Valid presets: ssh, kill-rdp"
                return
            }
        }
    }

    if ($Kill) {
        $custom = $Kill -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($custom.Count -gt 0) {
            Write-Status INFO "Custom kill list: $($custom -join ', ')"
            foreach ($p in $custom) { $targets.Add($p) }
        }
    }

    if ($targets.Count -eq 0) {
        Write-Status ERROR "No processes specified. Use -Preset <ssh|kill-rdp> and/or -Kill 'proc1,proc2'."
        return
    }

    $unique     = $targets | Select-Object -Unique
    $savedState = @{}

    foreach ($proc in $unique) {
        $svcName = $serviceMap[$proc]

        if ($svcName) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                $savedState[$svcName] = $svc.StartType.ToString()
                Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                Write-Status OK "Disabled: $proc"
            } else {
                Write-Status WARNING "Not running: $proc"
            }
        } else {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
                Write-Status OK "Stopped: $proc"
            } else {
                Write-Status WARNING "Not running: $proc"
            }
        }
    }

    if ($savedState.Count -gt 0) {
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        $mergedState = @{}
        if (Test-Path $stateFile) {
            $existingRaw = Get-Content -Path $stateFile -Raw -ErrorAction SilentlyContinue
            if ($existingRaw) {
                try {
                    ($existingRaw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
                        $mergedState[$_.Name] = $_.Value
                    }
                } catch { }
            }
        }
        foreach ($k in $savedState.Keys) { $mergedState[$k] = $savedState[$k] }
        $mergedState | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    }

    Write-Status OK "Optimize complete."
}
