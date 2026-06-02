function Invoke-Install {
    param([string]$Apps)

    if (-not $Apps) {
        Write-Status ERRO "Specify apps with -Apps (e.g.: 'Git.Git,Microsoft.VSCode')."
        return
    }

    $list = $Apps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($list.Count -eq 0) {
        Write-Status ERRO "No valid app in the provided list."
        return
    }

    Write-Status INFO "Ensuring winget is available..."
    try {
        Install-WinUtilWinget
    } catch {
        Write-Status ERRO "Failed to prepare winget: $($_.Exception.Message)"
        return
    }

    Write-Status INFO "Installing: $($list -join ', ')"
    try {
        Install-WinUtilProgramWinget -Action Install -Programs $list
        Write-Status OK "Installation complete."
    } catch {
        Write-Status ERRO $_.Exception.Message
    }
}
