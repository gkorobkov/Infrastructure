<#
.SYNOPSIS
Offline Pester 3+ checks. No installation, provider account or external HTTP traffic.
.EXAMPLE
Invoke-Pester .\tunnels\tests\tunnels-scripts.Tests.ps1
#>
$tunnelsRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $tunnelsRoot 'tunnels-common.ps1')

Describe 'Tunnel input and URLs' {
    It 'accepts loopback and a query string' {
        { Assert-TunnelInput 5678 '/webhook/a?x=1&y=2' '127.0.0.1' '/' } | Should Not Throw
        { Assert-TunnelInput 8000 '/' '::1' '/health' } | Should Not Throw
    }
    It 'rejects invalid ports, remote hosts and dangerous paths' {
        { Assert-TunnelInput 0 '/' 'localhost' '/' } | Should Throw
        { Assert-TunnelInput 65536 '/' 'localhost' '/' } | Should Throw
        { Assert-TunnelInput 5678 '/' 'example.com' '/' } | Should Throw
        foreach ($path in @('//remote/path', 'hook', "/hook`r`nx", '/x\y', '/x#fragment', '/x%0d%0a')) {
            { Assert-TunnelInput 5678 $path 'localhost' '/' } | Should Throw
        }
    }
    It 'formats IPv6 and preserves query strings literally' {
        Get-TunnelOrigin '::1' 8000 | Should Be 'http://[::1]:8000'
        Join-TunnelWebhook 'https://demo.trycloudflare.com/' '/webhook/a?x=1&y=2' | Should Be 'https://demo.trycloudflare.com/webhook/a?x=1&y=2'
    }
    It 'extracts provider URLs from output' {
        Get-TunnelPublicUrl 'INFO | https://demo.trycloudflare.com |' cloudflare | Should Be 'https://demo.trycloudflare.com'
        Get-TunnelPublicUrl 'your url is: https://demo.loca.lt' localtunnel | Should Be 'https://demo.loca.lt'
        Get-TunnelPublicUrl 'url=https://demo.ngrok-free.app' ngrok | Should Be 'https://demo.ngrok-free.app'
        Get-TunnelPublicUrl 'http://demo.trycloudflare.com' cloudflare | Should BeNullOrEmpty
        Get-TunnelPublicUrl 'https://demo.trycloudflare.com.evil.example' cloudflare | Should BeNullOrEmpty
    }
}

Describe 'Local checks and installation consent' {
    It 'rejects a closed local port' {
        Mock Test-TunnelTcp { $false }
        { Assert-TunnelServer localhost 5678 'http://localhost:5678' '/' } | Should Throw
    }
    It 'accepts HTTP 401, 403 and 404 as HTTP reachability' {
        Mock Test-TunnelTcp { $true }
        foreach ($value in @(401,403,404)) {
            Mock Get-TunnelHttpStatus { $value }
            { Assert-TunnelServer localhost 5678 'http://localhost:5678' '/' } | Should Not Throw
        }
    }
    It 'rejects TCP without HTTP' {
        Mock Test-TunnelTcp { $true }
        Mock Get-TunnelHttpStatus { 0 }
        { Assert-TunnelServer localhost 5678 'http://localhost:5678' '/' } | Should Throw
    }
    It 'detects missing commands' {
        Get-TunnelCommand 'infrastructure-nonexistent-tool-91.exe' | Should BeNullOrEmpty
    }
    It 'does not install after refusal' {
        Mock Read-Host { 'N' }
        { Request-TunnelInstall -Name 'test' } | Should Throw
    }
    It 'does not prompt when installation was explicitly permitted' {
        Mock Read-Host { throw 'Unexpected prompt' }
        { Request-TunnelInstall -Name 'test' -InstallIfMissing } | Should Not Throw
    }
    It 'gives a manual alternative when winget is unavailable' {
        Mock Get-TunnelCommand { $null }
        { Install-TunnelTool test 'https://example.com' -InstallIfMissing } | Should Throw
    }
}

Describe 'Provider state and safe diagnostics' {
    It 'does not query a different process on the selected API port' {
        Mock Get-NetTCPConnection { [pscustomobject]@{OwningProcess=123} }
        Mock Invoke-RestMethod { throw 'Must not query a foreign API' }
        Get-TunnelNgrokUrl 45000 'http://127.0.0.1:5678' 456 | Should BeNullOrEmpty
        Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly
    }
    It 'rejects invalid ngrok config and conflicting API port before installation' {
        Mock Install-TunnelTool { throw 'Must not install' }
        { Start-TunnelSession -Provider ngrok -Port 5678 -WebhookPath /hook -LocalHost localhost -NgrokConfig 'C:\nonexistent-tunnels-fixture.yml' } | Should Throw
        { Start-TunnelSession -Provider ngrok -Port 5678 -WebhookPath /hook -LocalHost localhost -NgrokApiPort 5678 } | Should Throw
        Assert-MockCalled Install-TunnelTool -Times 0 -Exactly
    }
    It 'classifies auth and account limits without echoing secrets' {
        Get-TunnelFailure 'ERR_NGROK_4018 secret-value' | Should Not Match 'secret-value'
        Get-TunnelFailure 'ERR_NGROK_108 secret-value' | Should Not Match 'secret-value'
        Get-TunnelFailure 'address already in use' | Should Match 'NgrokApiPort'
    }
    It 'uses only the tunnel matching the owned API and origin' {
        Mock Invoke-RestMethod { [pscustomobject]@{ tunnels = @(
            [pscustomobject]@{config = @{addr='http://127.0.0.1:9000'}; public_url='https://wrong.example.com'},
            [pscustomobject]@{config = @{addr='http://127.0.0.1:5678'}; public_url='https://custom.example.com'}
        ) } }
        Get-TunnelNgrokUrl 45000 'http://127.0.0.1:5678' | Should Be 'https://custom.example.com'
        Assert-MockCalled Invoke-RestMethod -ParameterFilter { $Uri -eq 'http://127.0.0.1:45000/api/tunnels' }
    }
    It 'rejects credentials or HTTP in an API URL' {
        Mock Invoke-RestMethod { [pscustomobject]@{ tunnels = @(
            [pscustomobject]@{config = @{addr='http://127.0.0.1:5678'}; public_url='https://user:secret@example.com'}
        ) } }
        Get-TunnelNgrokUrl 45000 'http://127.0.0.1:5678' | Should BeNullOrEmpty
    }
    It 'reports early exit without copying raw output into the error' {
        $fake = New-Object PSObject -Property @{Process = [pscustomobject]@{HasExited=$true}}
        $fake | Add-Member ScriptMethod ReadLine { return $null }
        { Wait-TunnelUrl $fake cloudflare 1 0 'http://localhost:5678' } | Should Throw
    }
    It 'enforces URL startup timeout' {
        $fake = New-Object PSObject -Property @{Process = [pscustomobject]@{HasExited=$false}}
        $fake | Add-Member ScriptMethod ReadLine { return $null }
        { Wait-TunnelUrl $fake cloudflare 1 0 'http://localhost:5678' } | Should Throw
    }
}

Describe 'Owned Windows client lifecycle' {
    It 'passes default parameter values through all three launchers and rejects a remote host before any action' {
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        foreach ($provider in @('cloudflare', 'ngrok', 'localtunnel')) {
            $script = Join-Path $tunnelsRoot "tunnels-start-$provider.ps1"
            Write-Host "Goal: Проверить безопасный отказ точки запуска $provider"
            Write-Host "RUN: powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -LocalHost example.com"
            $output = & $shell -NoProfile -ExecutionPolicy Bypass -File $script -LocalHost example.com
            $LASTEXITCODE | Should Be 1
            ($output -join ' ') | Should Match 'LocalHost'
        }
    }
    It 'kills descendants without stopping an unrelated process' {
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $other = Start-Process -FilePath $shell -ArgumentList '-NoProfile -Command "Start-Sleep 30"' -WindowStyle Hidden -PassThru
        $client = $null
        try {
            $code = '$p = Start-Process powershell.exe -ArgumentList ''-NoProfile -Command "Start-Sleep 30"'' -WindowStyle Hidden -PassThru; [Console]::Out.WriteLine("CHILD=" + $p.Id); Start-Sleep 30'
            $client = New-TunnelClient $shell @('-NoProfile','-Command',$code)
            $childId = 0
            $watch = [Diagnostics.Stopwatch]::StartNew()
            while ($childId -eq 0 -and $watch.Elapsed.TotalSeconds -lt 10) {
                $line = $client.ReadLine()
                if ($line -match '^CHILD=(\d+)$') { $childId = [int]$Matches[1] }
                Start-Sleep -Milliseconds 50
            }
            $childId | Should BeGreaterThan 0
            $client.Dispose(); $client = $null
            Start-Sleep -Milliseconds 300
            Get-Process -Id $childId -ErrorAction SilentlyContinue | Should BeNullOrEmpty
            $other.Refresh()
            $other.HasExited | Should Be $false
        } finally {
            if ($client) { $client.Dispose() }
            if (-not $other.HasExited) { $other.Kill() }
            $other.Dispose()
        }
    }
    It 'drains large stdout and stderr and terminates its own process on disposal' {
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $code = '1..4000 | ForEach-Object { [Console]::Out.WriteLine("output"); [Console]::Error.WriteLine("error") }; [Console]::Out.WriteLine("https://fixture.trycloudflare.com"); Start-Sleep 30'
        $client = $null
        try {
            $client = New-TunnelClient $shell @('-NoProfile','-Command',$code)
            $ownedId = $client.Process.Id
            Wait-TunnelUrl $client cloudflare 15 0 'http://localhost:5678' | Should Be 'https://fixture.trycloudflare.com'
        } finally { if ($client) { $client.Dispose() } }
        Start-Sleep -Milliseconds 300
        Get-Process -Id $ownedId -ErrorAction SilentlyContinue | Should BeNullOrEmpty
    }
}
