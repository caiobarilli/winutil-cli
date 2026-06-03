function Invoke-Optimize {
    param(
        [string]$Preset,
        [string]$Kill,
        [switch]$Undo,
        [string]$KeepUser
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
                # ── SESSION LOGOFF ─────────────────────────────────────────────
                $currentProc      = Get-Process -Id $PID -ErrorAction SilentlyContinue
                $currentSessionId = if ($currentProc) { $currentProc.SessionId } else { -1 }

                $rawSessions  = @(query session)
                $discSessions = [System.Collections.Generic.List[object]]::new()

                if ($rawSessions.Count -gt 1) {
                    foreach ($line in $rawSessions | Select-Object -Skip 1) {
                        $clean  = $line.TrimStart('>', ' ')
                        $tokens = ($clean -split '\s{2,}') | Where-Object { $_ -ne '' }
                        if ($tokens.Count -lt 2) { continue }

                        $idIdx = -1
                        for ($i = 0; $i -lt $tokens.Count; $i++) {
                            if ($tokens[$i] -match '^\d+$') { $idIdx = $i; break }
                        }
                        if ($idIdx -lt 0 -or ($idIdx + 1) -ge $tokens.Count) { continue }

                        $sid   = [int]$tokens[$idIdx]
                        $state = $tokens[$idIdx + 1]
                        $uname = if ($idIdx -ge 1) { $tokens[$idIdx - 1] } else { '' }

                        if ($state -ne 'Disc')           { continue }
                        if ($sid  -eq 0)                 { continue }
                        if ($sid  -eq $currentSessionId) { continue }

                        $discSessions.Add([PSCustomObject]@{ Id = $sid; Username = $uname })
                    }
                }

                $logoffCount = 0
                if ($discSessions.Count -eq 0) {
                    Write-Status INFO "No disconnected RDP sessions found."
                } else {
                    Write-Status INFO "Found $($discSessions.Count) disconnected RDP session(s)..."
                    foreach ($sess in $discSessions) {
                        if ($KeepUser -and ($sess.Username -ieq $KeepUser)) {
                            Write-Status WARNING "Skipped session $($sess.Id) ($($sess.Username)) - protected by -KeepUser"
                            continue
                        }
                        logoff $sess.Id
                        Write-Status OK "Logged off session $($sess.Id) ($($sess.Username))"
                        $logoffCount++
                    }

                    if ($logoffCount -gt 0) {
                        Write-Status INFO "Waiting for session processes to exit..."
                        $deadline = (Get-Date).AddSeconds(10)
                        while ((Get-Date) -lt $deadline) {
                            $remaining = Get-Process -Name 'rdpclip', 'userinit' -ErrorAction SilentlyContinue
                            if (-not $remaining) { break }
                            Start-Sleep -Seconds 2
                        }
                        Write-Status OK "Session cleanup complete."
                    }
                }

                # ── PROCESS CLEANUP ────────────────────────────────────────────
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
