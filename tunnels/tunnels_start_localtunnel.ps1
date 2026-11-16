<#
.SYNOPSIS
??????? HTTPS-??????? localtunnel ? ?????????? HTTP-???????.
.DESCRIPTION
????????? ??????, ?????????? ????????? ??????? ? ??????? WEBHOOK URL.
??????? ???????? ?? Ctrl+C. ?? ???????? ????????? ?????????? ? ?? ?????????? POST.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tunnels_start_localtunnel.ps1 -Port 5678 -WebhookPath /webhook/my-agent
.EXAMPLE
.\tunnels_start_localtunnel.ps1 -Port 8000 -WebhookPath '/api/hook?mode=demo' -InstallIfMissing
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$Port = 5678,
    [string]$WebhookPath = '/webhook/my-agent',
    [string]$LocalHost = '127.0.0.1',
    [switch]$InstallIfMissing,
    [switch]$SkipPublicCheck,
    [switch]$VerboseOutput,
    [string]$HealthPath = '/',
    [ValidateRange(1, 600)][int]$StartupTimeoutSeconds = 90
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'tunnels_common.ps1')
    $sessionParameters = @{
        Provider = 'localtunnel'; Port = $Port; WebhookPath = $WebhookPath; LocalHost = $LocalHost
        InstallIfMissing = $InstallIfMissing; SkipPublicCheck = $SkipPublicCheck
        VerboseOutput = $VerboseOutput; HealthPath = $HealthPath; StartupTimeoutSeconds = $StartupTimeoutSeconds
    }
    Start-TunnelSession @sessionParameters
} catch {
    # Known errors are authored messages; native process output is never echoed.
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
