function Invoke-DNS {
    param(
        [string]$Provider,
        [string]$PrimaryDNS,
        [string]$SecondaryDNS
    )

    if (-not $Provider) {
        Write-Status ERRO "Specify the provider with -Provider (e.g.: cloudflare, google, quad9)."
        return
    }

    # access is case-insensitive
    $valid = @($sync.configs.dns.PSObject.Properties.Name)
    if ($Provider -notin $valid -and $Provider -notin @('Default', 'DHCP')) {
        Write-Status ERRO "Provider '$Provider' does not exist in dns.json."
        Write-Status INFO  "Available: $($valid -join ', ')"
        return
    }

    if ($Provider -ieq 'custom' -and -not $PrimaryDNS) {
        Write-Status ERRO "Provider 'custom' requires -PrimaryDNS to be specified."
        return
    }

    Write-Status INFO "Applying DNS '$Provider'..."
    try {
        Set-WinUtilDNS -DNSProvider $Provider
        Write-Status OK "DNS '$Provider' applied."
    } catch {
        Write-Status ERRO $_.Exception.Message
    }
}
