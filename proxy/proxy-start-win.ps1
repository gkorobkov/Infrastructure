<#
.SYNOPSIS
Check prerequisites, offer a private Node.js installation, then start Universal HTTP Proxy.
.EXAMPLE
.\proxy-start-win.ps1 --allow-origin https://client.example
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$proxyArgs = $args
function Test-ProxyNode([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try { return ((& $Path -p 'Number(process.versions.node.split(String.fromCharCode(46))[0]) >= 22' 2>$null) -eq 'true' -and $LASTEXITCODE -eq 0) } catch { return $false }
}
try {
    Set-Location -LiteralPath $PSScriptRoot
    Write-Host '[CHECK] Proxy entry point'
    if (-not (Test-Path -LiteralPath 'src/proxy-cli.js')) { throw 'Missing src/proxy-cli.js; download the complete repository.' }
    Write-Host '[OK] Proxy entry point found'
    $runtime = Join-Path $PSScriptRoot '.proxy-runtime'
    $node = Join-Path $runtime 'node/node.exe'
    Write-Host '[CHECK] Node.js 22+'
    if (-not (Test-ProxyNode $node)) {
        $command = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($command) { $node = $command.Source } else { $node = '' }
        if (-not (Test-ProxyNode $node)) {
            Write-Host '[MISSING] Supported Node.js'
            $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
            switch ($arch) { 'AMD64' { $arch = 'x64' } 'ARM64' { $arch = 'arm64' } default { throw 'Supported architectures: x64 and ARM64.' } }
            $version = 'v24.22.3'
            $file = "node-$version-win-$arch.zip"
            $base = "https://nodejs.org/dist/$version"
            Write-Host '[OK] PowerShell download, ZIP extraction and SHA-256 tools available'
            Write-Host "Node.js $version ($arch) is needed. Download approximately 35-45 MB; allow 200 MB disk space."
            if ([Console]::IsInputRedirected) { throw 'Run interactively to approve installation.' }
            $answer = Read-Host "Install into $runtime (no system changes)? [Y/n]"
            if ($answer -notin @('', 'y', 'yes')) { throw 'Installation declined; proxy was not started.' }
            $null = New-Item -ItemType Directory -Path $runtime -Force
            $stage = Join-Path $runtime ('install.' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $stage
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Host "Goal: Download official Node.js archive.`nRUN: Invoke-WebRequest $base/$file"
                Invoke-WebRequest "$base/$file" -OutFile (Join-Path $stage $file) -UseBasicParsing
                Write-Host "Goal: Download official checksums.`nRUN: Invoke-WebRequest $base/SHASUMS256.txt"
                $checksums = (Invoke-WebRequest "$base/SHASUMS256.txt" -UseBasicParsing).Content
                $match = [regex]::Match($checksums, '(?m)^([a-f0-9]{64})\s+' + [regex]::Escape($file) + '\r?$')
                Write-Host "Goal: Verify archive SHA-256.`nRUN: Get-FileHash -Algorithm SHA256"
                if (-not $match.Success -or (Get-FileHash (Join-Path $stage $file) -Algorithm SHA256).Hash -ne $match.Groups[1].Value) { throw 'Archive checksum mismatch or missing checksum.' }
                Write-Host "Goal: Extract Node.js.`nRUN: Expand-Archive"
                Expand-Archive -LiteralPath (Join-Path $stage $file) -DestinationPath $stage
                $extracted = Join-Path $stage "node-$version-win-$arch"
                if (-not (Test-ProxyNode (Join-Path $extracted 'node.exe'))) { throw 'Downloaded Node.js cannot run on this OS.' }
                $destination = Join-Path $runtime 'node'
                if (Test-Path -LiteralPath $destination) { throw 'An unusable bundled runtime exists. Move .proxy-runtime/node aside and retry.' }
                Move-Item -LiteralPath $extracted -Destination $destination
                $node = Join-Path $destination 'node.exe'
            } finally {
                if ((Split-Path $stage -Parent) -ne $runtime -or (Split-Path $stage -Leaf) -notlike 'install.*') { throw 'Unsafe cleanup path.' }
                Remove-Item -LiteralPath $stage -Recurse -Force
            }
        }
    }
    Write-Host "[OK] Node.js: $(& $node --version)"
    Write-Host "Goal: Start Universal HTTP Proxy.`nRUN: node src/proxy-cli.js (requested options forwarded)"
    & $node (Join-Path $PSScriptRoot 'src/proxy-cli.js') @proxyArgs
    exit $LASTEXITCODE
} catch { Write-Host ('[ERROR] ' + $_.Exception.Message); exit 1 }
