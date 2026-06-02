#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5+ tests for winutil-cli.ps1
.DESCRIPTION
    Covers sanity checks, parameter validation and mock-based execution.
    Output saved to C:\log\DD.MM.AAAA\pester-winutil-cli.txt
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
    It "-Action dns without -Provider returns [ ERRO ]" {
        $output = (Invoke-DNS -Provider '') 6>&1 | Out-String
        $output | Should -Match '\[ ERRO \]'
    }

    It "-Action install without -Apps returns [ ERRO ]" {
        $output = (Invoke-Install -Apps '') 6>&1 | Out-String
        $output | Should -Match '\[ ERRO \]'
    }

    It "-Action dns -Provider custom without -PrimaryDNS returns [ ERRO ]" {
        $output = (Invoke-DNS -Provider 'custom' -PrimaryDNS '') 6>&1 | Out-String
        $output | Should -Match '\[ ERRO \]'
    }
}

# ==============================================================
# EXECUTION WITH MOCK
# ==============================================================
Describe "Execution with Mock" {

    Context "-Action audit" {
        It "generates the 8 audit files in C:\log\DD.MM.AAAA\" {
            Invoke-Audit
            $logDir    = "C:\log\$(Get-Date -Format 'dd.MM.yyyy')"
            $esperados = @(
                '01-sistema.txt', '02-hardware.txt', '03-processos.txt',
                '04-servicos.txt', '05-startup.txt',  '06-rede.txt',
                '07-tarefas.txt',  '08-hyperv.txt'
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
}
