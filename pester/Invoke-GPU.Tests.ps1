#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5+ tests for scripts/Invoke-GPU.ps1
.DESCRIPTION
    Mock-based unit tests for each SubAction and the interactive menu dispatch.
    Output saved to C:\log\DD.MM.YYYY\pester-invoke-gpu.txt
#>

BeforeAll {
    $Script:RootDir = Split-Path $PSScriptRoot -Parent
    $Script:LogDate = Get-Date -Format 'dd.MM.yyyy'
    $Script:LogDir  = "C:\log\$($Script:LogDate)"
    $Script:LogFile = "$($Script:LogDir)\pester-invoke-gpu.txt"

    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }

    try { Start-Transcript -Path $Script:LogFile -Force | Out-Null } catch {}

    $global:sync = [hashtable]::Synchronized(@{})
    $global:sync.configs = @{}

    # Load Write-Status from winutil-cli.ps1 via AST (no side-effects)
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

    # Load Invoke-GPU
    . (Join-Path $Script:RootDir 'scripts\Invoke-GPU.ps1')
}

AfterAll {
    try { Stop-Transcript | Out-Null } catch {}
}

# ==============================================================
# SANITY
# ==============================================================
Describe "Invoke-GPU - Sanity" {

    It "Invoke-GPU.ps1 exists in scripts/" {
        Test-Path (Join-Path $Script:RootDir 'scripts\Invoke-GPU.ps1') | Should -BeTrue
    }

    It "Invoke-GPU.ps1 has no syntax errors" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $Script:RootDir 'scripts\Invoke-GPU.ps1'),
            [ref]$null, [ref]$errors
        ) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "Invoke-GPU function is available after dot-sourcing" {
        Get-Command -Name 'Invoke-GPU' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

# ==============================================================
# SUBACTION — unknown
# ==============================================================
Describe "Invoke-GPU - Unknown SubAction" {

    It "emits [ ERROR ] for an unrecognised subaction" {
        $output = (Invoke-GPU -SubAction 'bogus') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "emits [ INFO ] listing valid options for an unrecognised subaction" {
        $output = (Invoke-GPU -SubAction 'bogus') 6>&1 | Out-String
        $output | Should -Match '\[ INFO \]'
        $output | Should -Match 'install'
    }
}

# ==============================================================
# SUBACTION — status
# ==============================================================
Describe "Invoke-GPU - SubAction status" {

    Context "process running, task registered" {
        It "emits [ OK ] for process and [ INFO ] for scheduled task" {
            Mock Get-Process      { [PSCustomObject]@{ Id = 1234 } } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
            Mock Get-ScheduledTask { [PSCustomObject]@{ TaskName = 'nvidia_gpu_exporter'; State = 'Ready' } }
            $output = (Invoke-GPU -SubAction 'status') 6>&1 | Out-String
            $output | Should -Match '\[ OK \]'
            $output | Should -Match '\[ INFO \]'
        }
    }

    Context "process stopped, task missing" {
        It "emits [ WARNING ] for both process and scheduled task" {
            Mock Get-Process      { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
            Mock Get-ScheduledTask { $null }
            $output = (Invoke-GPU -SubAction 'status') 6>&1 | Out-String
            ($output -split '\[ WARNING \]').Count - 1 | Should -BeGreaterOrEqual 2
        }
    }
}

# ==============================================================
# SUBACTION — start
# ==============================================================
Describe "Invoke-GPU - SubAction start" {

    It "emits [ INFO ] when process is already running" {
        Mock Get-Process { [PSCustomObject]@{ Id = 42 } } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        $output = (Invoke-GPU -SubAction 'start') 6>&1 | Out-String
        $output | Should -Match '\[ INFO \]'
        $output | Should -Match 'already running'
    }

    It "emits [ ERROR ] when exe is missing and process is not running" {
        Mock Get-Process { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Test-Path   { $false }
        $output = (Invoke-GPU -SubAction 'start') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "calls Start-Process and emits [ OK ] when exe exists and process is not running" {
        Mock Get-Process    { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Test-Path      { $true }
        Mock Start-Process  { }
        $output = (Invoke-GPU -SubAction 'start') 6>&1 | Out-String
        $output | Should -Match '\[ OK \]'
        Should -Invoke -CommandName Start-Process -Times 1
    }
}

# ==============================================================
# SUBACTION — stop
# ==============================================================
Describe "Invoke-GPU - SubAction stop" {

    It "emits [ WARNING ] when process is not running" {
        Mock Get-Process { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        $output = (Invoke-GPU -SubAction 'stop') 6>&1 | Out-String
        $output | Should -Match '\[ WARNING \]'
    }

    It "calls Stop-Process and emits [ OK ] when process is running" {
        Mock Get-Process  { [PSCustomObject]@{ Id = 99 } } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Stop-Process { }
        $output = (Invoke-GPU -SubAction 'stop') 6>&1 | Out-String
        $output | Should -Match '\[ OK \]'
        Should -Invoke -CommandName Stop-Process -Times 1
    }
}

# ==============================================================
# SUBACTION — metrics
# ==============================================================
Describe "Invoke-GPU - SubAction metrics" {

    It "emits [ INFO ] with the metrics URL" {
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = ("# TYPE nvidia_smi_power_watts gauge`n" * 25) }
        }
        $output = (Invoke-GPU -SubAction 'metrics') 6>&1 | Out-String
        $output | Should -Match '\[ INFO \]'
        $output | Should -Match '9835'
    }

    It "emits [ WARNING ] when port is not reachable" {
        Mock Invoke-WebRequest { throw "Connection refused" }
        $output = (Invoke-GPU -SubAction 'metrics') 6>&1 | Out-String
        $output | Should -Match '\[ WARNING \]'
    }
}

# ==============================================================
# SUBACTION — install
# ==============================================================
Describe "Invoke-GPU - SubAction install" {

    It "emits [ OK ] with port 9835 message after successful install" {
        Mock Test-Path          { $false }
        Mock New-Item           { }
        Mock Invoke-RestMethod  {
            [PSCustomObject]@{
                tag_name = 'v1.2.0'
                assets   = @(
                    [PSCustomObject]@{
                        name                 = 'nvidia_gpu_exporter_1.2.0_windows_x86_64.zip'
                        browser_download_url = 'http://example.com/nvidia_gpu_exporter.zip'
                    }
                )
            }
        }
        Mock Invoke-WebRequest  { }
        Mock Expand-Archive     { }
        Mock Get-ChildItem      {
            [PSCustomObject]@{ FullName = 'C:\WinUtil\nvidia_gpu_exporter\nvidia_gpu_exporter.exe' }
        } -ParameterFilter { $Filter -eq '*.exe' }
        Mock Remove-Item        { }
        Mock Get-Process        { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Start-Process      { }
        Mock Register-ScheduledTask { }
        Mock New-ScheduledTaskAction   { [PSCustomObject]@{} }
        Mock New-ScheduledTaskTrigger  { [PSCustomObject]@{} }
        Mock New-ScheduledTaskSettingsSet { [PSCustomObject]@{} }
        Mock New-ScheduledTaskPrincipal   { [PSCustomObject]@{} }
        Mock Get-NetFirewallRule { $null }
        Mock New-NetFirewallRule { }
        $output = (Invoke-GPU -SubAction 'install') 6>&1 | Out-String
        $output | Should -Match '\[ OK \]'
        $output | Should -Match '9835'
    }

    It "emits [ ERROR ] when GitHub API returns no matching asset" {
        Mock Test-Path         { $false }
        Mock New-Item          { }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                tag_name = 'v1.2.0'
                assets   = @()
            }
        }
        $output = (Invoke-GPU -SubAction 'install') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "emits [ ERROR ] when download fails" {
        Mock Test-Path         { $false }
        Mock New-Item          { }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                tag_name = 'v1.2.0'
                assets   = @(
                    [PSCustomObject]@{
                        name                 = 'nvidia_gpu_exporter_1.2.0_windows_x86_64.zip'
                        browser_download_url = 'http://example.com/nvidia_gpu_exporter.zip'
                    }
                )
            }
        }
        Mock Invoke-WebRequest { throw "Network error" }
        $output = (Invoke-GPU -SubAction 'install') 6>&1 | Out-String
        $output | Should -Match '\[ ERROR \]'
    }

    It "skips download and emits [ INFO ] when exe already exists" {
        Mock Test-Path { $true }
        Mock Invoke-RestMethod { throw "should not be called" }
        Mock Get-Process { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Start-Process { }
        Mock Register-ScheduledTask { }
        Mock New-ScheduledTaskAction   { [PSCustomObject]@{} }
        Mock New-ScheduledTaskTrigger  { [PSCustomObject]@{} }
        Mock New-ScheduledTaskSettingsSet { [PSCustomObject]@{} }
        Mock New-ScheduledTaskPrincipal   { [PSCustomObject]@{} }
        Mock Get-NetFirewallRule { $null }
        Mock New-NetFirewallRule { }
        $output = (Invoke-GPU -SubAction 'install') 6>&1 | Out-String
        $output | Should -Match '\[ INFO \]'
        $output | Should -Match 'already installed'
        Should -Invoke -CommandName Invoke-RestMethod -Times 0
    }
}

# ==============================================================
# SUBACTION — uninstall
# ==============================================================
Describe "Invoke-GPU - SubAction uninstall" {

    It "stops process, removes task, firewall rule, and directory" {
        Mock Get-Process          { [PSCustomObject]@{ Id = 7 } } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Stop-Process         { }
        Mock Get-ScheduledTask    { [PSCustomObject]@{ TaskName = 'nvidia_gpu_exporter' } }
        Mock Unregister-ScheduledTask { }
        Mock Get-NetFirewallRule  { [PSCustomObject]@{ DisplayName = 'WinUtil - nvidia_gpu_exporter 9835' } }
        Mock Remove-NetFirewallRule { }
        Mock Test-Path            { $true }
        Mock Remove-Item          { }
        $output = (Invoke-GPU -SubAction 'uninstall') 6>&1 | Out-String
        Should -Invoke -CommandName Stop-Process              -Times 1
        Should -Invoke -CommandName Unregister-ScheduledTask  -Times 1
        Should -Invoke -CommandName Remove-NetFirewallRule    -Times 1
        Should -Invoke -CommandName Remove-Item               -Times 1
        $output | Should -Match '\[ OK \]'
    }

    It "emits [ INFO ] for each resource not found during uninstall" {
        Mock Get-Process          { $null } -ParameterFilter { $Name -eq 'nvidia_gpu_exporter' }
        Mock Get-ScheduledTask    { $null }
        Mock Get-NetFirewallRule  { $null }
        Mock Test-Path            { $false }
        $output = (Invoke-GPU -SubAction 'uninstall') 6>&1 | Out-String
        ($output -split '\[ INFO \]').Count - 1 | Should -BeGreaterOrEqual 3
    }
}
