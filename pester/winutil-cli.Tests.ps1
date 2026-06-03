#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5+ tests for winutil-cli.ps1
.DESCRIPTION
    Covers sanity checks, parameter validation and mock-based execution.
    Output saved to C:\log\DD.MM.YYYY\pester-winutil-cli.txt
#>

BeforeAll {
    $Script:RootDir = Split-Path $PSScriptRoot -Parent
    $Script:LogDate = Get-Date -Format 'dd.MM.yyyy'
    $Script:LogDir  = "C:\log\$($Script:LogDate)"
    $Script:LogFile = "$($Script:LogDir)\pester-winutil-cli.txt"

    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }

    try { Start-Transcript -Path $Script:LogFile -Force | Out-Null } catch {}

    # Set up global $sync (required by action functions)
    $global:sync = [hashtable]::Synchronized(@{})
    $global:sync.configs = @{}

    $configPath = Join-Path $Script:RootDir 'config'
    foreach ($name in 'dns', 'tweaks', 'preset', 'feature', 'applications') {
        $file = Join-Path $configPath "$name.json"
        if (Test-Path $file) {
            try { $global:sync.configs.$name = Get-Content $file -Raw | ConvertFrom-Json } catch {}
        }
    }

    # Load private/public functions (Set-WinUtilDNS, Remove-WinUtilAPPX, etc.)
    foreach ($subDir in @('functions\private', 'functions\public')) {
        $full = Join-Path $Script:RootDir $subDir
        if (Test-Path $full) {
            Get-ChildItem -Path $full -Filter '*.ps1' -File | ForEach-Object {
                try { . $_.FullName } catch {}
            }
        }
    }

    # Load action functions from scripts/Invoke-*.ps1
    $scriptsDir = Join-Path $Script:RootDir 'scripts'
    if (Test-Path $scriptsDir) {
        Get-ChildItem -Path $scriptsDir -Filter 'Invoke-*.ps1' -File | ForEach-Object {
            try { . $_.FullName } catch {}
        }
    }

    # Extract and load helper functions from winutil-cli.ps1 via AST (without running the script)
    $scriptPath  = Join-Path $Script:RootDir 'winutil-cli.ps1'
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$null, [ref]$parseErrors
    )
    $ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ) | ForEach-Object {
        Invoke-Expression $_.Extent.Text
    }

    # $root used by Invoke-Audit and other action functions
    $global:root = $Script:RootDir
}

AfterAll {
    try { Stop-Transcript | Out-Null } catch {}
}

# ==============================================================
# SANITY
# ==============================================================
Describe "Sanity" {

    It "winutil-cli.ps1 exists in root" {
        Test-Path (Join-Path $Script:RootDir 'winutil-cli.ps1') | Should -BeTrue
    }

    It "audit/audit.ps1 exists" {
        Test-Path (Join-Path $Script:RootDir 'audit\audit.ps1') | Should -BeTrue
    }

    Context "JSONs in config/" {
        It "<_>.json exists and is valid JSON" -ForEach @(
            'dns', 'tweaks', 'preset', 'feature', 'applications'
        ) {
            $file = Join-Path $Script:RootDir "config\$_.json"
            Test-Path $file | Should -BeTrue
            { Get-Content $file -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    It "Functions in functions/ have no syntax errors" {
        $invalidos = @()
        Get-ChildItem -Path (Join-Path $Script:RootDir 'functions') -Recurse -Filter '*.ps1' -File |
            ForEach-Object {
                $erros = $null
                [System.Management.Automation.Language.Parser]::ParseFile(
                    $_.FullName, [ref]$null, [ref]$erros
                ) | Out-Null
                if ($erros.Count -gt 0) { $invalidos += $_.Name }
            }
        $invalidos | Should -BeNullOrEmpty -Because "all .ps1 files in functions/ must have valid syntax"
    }
}

# ==============================================================
# PARAMETER VALIDATION
# ==============================================================
Describe "Parameter Validation" {

    # 6>&1 redirects the Information stream (Write-Host PS 5+) to the pipeline
    It "-Action dns without -Provider returns [ ERROR ]" {
        $output = (Invoke-DNS -Provider '') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "-Action install without -Apps returns [ ERROR ]" {
        $output = (Invoke-Install -Apps '') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "-Action dns -Provider custom without -PrimaryDNS returns [ ERROR ]" {
        $output = (Invoke-DNS -Provider 'custom' -PrimaryDNS '') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "-Action optimize without -Preset or -Kill returns [ ERROR ]" {
        $output = (Invoke-Optimize) 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "-Action optimize with unknown -Preset returns [ ERROR ]" {
        $output = (Invoke-Optimize -Preset 'invalid') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }
}

# ==============================================================
# EXECUTION WITH MOCK
# ==============================================================
Describe "Execution with Mock" {

    Context "-Action audit" {
        It "generates the 8 audit files in C:\log\DD.MM.YYYY\" {
            Invoke-Audit
            $logDir    = "C:\log\$(Get-Date -Format 'dd.MM.yyyy')"
            $esperados = @(
                '01-system.txt', '02-hardware.txt', '03-processes.txt',
                '04-services.txt', '05-startup.txt',  '06-network.txt',
                '07-tasks.txt',  '08-hyperv.txt'
            )
            foreach ($f in $esperados) {
                Test-Path (Join-Path $logDir $f) |
                    Should -BeTrue -Because "audit must generate the file $f"
            }
        }
    }

    Context "-Action performance" {
        It "calls powercfg without throwing an exception" {
            # Returns simulated list already containing the original GUID (Priority 1)
            Mock powercfg {
                "Power Scheme GUID: e9a42b02-d5df-448d-aa00-03f14749eb61  (Ultimate Performance)"
            }
            { Invoke-Performance -State 'on' } | Should -Not -Throw
        }
    }

    Context "-Action dns -Provider cloudflare" {
        It "calls Set-WinUtilDNS with the correct provider" {
            Mock Set-WinUtilDNS { }
            Invoke-DNS -Provider 'cloudflare'
            Should -Invoke -CommandName Set-WinUtilDNS -Times 1 `
                -ParameterFilter { $DNSProvider -eq 'cloudflare' }
        }
    }

    Context "-Action processes" {
        It "Invoke-Processes returns 30 lines of process output" {
            $output = Invoke-Processes 6>&1 | Out-String
            $lines = ($output -split "`n") | Where-Object { $_ -match '\S' }
            $lines.Count | Should -BeGreaterOrEqual 30
        }
    }

    Context "-Action optimize" {
        It "-Preset ssh calls Set-Service Disabled and Stop-Service for service-backed, Stop-Process for process-only" {
            Mock Get-Process { [PSCustomObject]@{ Name = 'mock' } }
            Mock Get-Service { [PSCustomObject]@{ Name = 'mock'; Status = 'Running'; StartType = 'Automatic' } }
            Mock Set-Service { }
            Mock Stop-Service { }
            Mock Stop-Process { }
            Mock Test-Path { $true }
            Mock Set-Content { }
            Invoke-Optimize -Preset 'ssh'
            # 3 service-backed: SearchHost, TextInputHost, OfficeClickToRun
            Should -Invoke -CommandName Set-Service  -Times 3
            Should -Invoke -CommandName Stop-Service -Times 3
            # 5 process-only: LogonUI, StartMenuExperienceHost, ShellExperienceHost, ShellHost, msedgewebview2
            Should -Invoke -CommandName Stop-Process -Times 5
        }

        It "-Kill stops each process in the comma-separated list" {
            Mock Get-Process { [PSCustomObject]@{ Name = 'mock' } }
            Mock Stop-Process { }
            Invoke-Optimize -Kill 'notepad,calc'
            Should -Invoke -CommandName Stop-Process -Times 2
        }

        It "-Preset ssh combined with -Kill stops preset + custom processes" {
            Mock Get-Process { [PSCustomObject]@{ Name = 'mock' } }
            Mock Get-Service { [PSCustomObject]@{ Name = 'mock'; Status = 'Running'; StartType = 'Automatic' } }
            Mock Set-Service { }
            Mock Stop-Service { }
            Mock Stop-Process { }
            Mock Test-Path { $true }
            Mock Set-Content { }
            Invoke-Optimize -Preset 'ssh' -Kill 'notepad'
            Should -Invoke -CommandName Stop-Service -Times 3
            # 5 process-only from preset + 1 custom kill
            Should -Invoke -CommandName Stop-Process -Times 6
        }

        It "not-running process emits [ WARNING ] instead of [ OK ]" {
            Mock Get-Process { $null }
            Mock Stop-Process { }
            $output = (Invoke-Optimize -Kill 'ghostproc') 6>&1 | Out-String
            $output | Should -Match '\[ WARNING \]'
            Should -Invoke -CommandName Stop-Process -Times 0
        }

        It "-Preset ssh does not throw" {
            Mock Get-Process { $null }
            Mock Get-Service { $null }
            Mock Set-Service { }
            Mock Stop-Process { }
            Mock Stop-Service { }
            { Invoke-Optimize -Preset 'ssh' } | Should -Not -Throw
        }

        It "-Undo restores services from state file and deletes it" {
            Mock Test-Path { $true } -ParameterFilter { $Path -eq 'C:\WinUtil\optimize-state.json' }
            Mock Get-Content { '{"WSearch":"Automatic","ClickToRunSvc":"Automatic"}' }
            Mock Set-Service  { }
            Mock Start-Service { }
            Mock Remove-Item { }
            Invoke-Optimize -Undo
            Should -Invoke -CommandName Set-Service   -Times 2
            Should -Invoke -CommandName Start-Service -Times 2
            Should -Invoke -CommandName Remove-Item   -Times 1
        }

        It "-Undo with missing state file emits [ ERROR ]" {
            Mock Test-Path { $false } -ParameterFilter { $Path -eq 'C:\WinUtil\optimize-state.json' }
            $output = (Invoke-Optimize -Undo) 6>&1 | Out-String
            $output | Should -Match '\[ ERROR \]'
        }

        It "-Preset kill-rdp calls Set-Service Disabled and Stop-Service for service-backed, Stop-Process for process-only" {
            Mock Get-Process { [PSCustomObject]@{ Name = 'mock' } }
            Mock Get-Service { [PSCustomObject]@{ Name = 'mock'; Status = 'Running'; StartType = 'Automatic' } }
            Mock Set-Service { }
            Mock Stop-Service { }
            Mock Stop-Process { }
            Mock Test-Path { $true }
            Mock Set-Content { }
            Invoke-Optimize -Preset 'kill-rdp'
            # 2 service-backed: SearchHost (WSearch), TextInputHost (TextInputManagementService)
            Should -Invoke -CommandName Set-Service  -Times 2
            Should -Invoke -CommandName Stop-Service -Times 2
            # 10 process-only: explorer, StartMenuExperienceHost, ShellExperienceHost, ShellHost,
            #                   msedgewebview2, dwm, sihost, RuntimeBroker, backgroundTaskHost, CrossDeviceResume
            Should -Invoke -CommandName Stop-Process -Times 10
        }

        It "-Preset kill-rdp does not throw" {
            Mock Get-Process { $null }
            Mock Get-Service { $null }
            Mock Set-Service { }
            Mock Stop-Process { }
            Mock Stop-Service { }
            { Invoke-Optimize -Preset 'kill-rdp' } | Should -Not -Throw
        }
    }
}
