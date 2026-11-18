<#
Test local launcher configuration without installing software or starting Docker.
Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\n8n-test-local.ps1
Example: run this command from the n8n directory on Windows 11.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'n8n-docker-compose-deploy-win.ps1')
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('n8n-local-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.env.local.example') -Destination $testDirectory
    $first = Initialize-LocalConfig $testDirectory
    $second = Initialize-LocalConfig $testDirectory
    if ($first.N8N_ENCRYPTION_KEY -ne $second.N8N_ENCRYPTION_KEY) { throw 'Encryption key changed on rerun.' }
    if ($first.N8N_RUNNERS_AUTH_TOKEN -ne $second.N8N_RUNNERS_AUTH_TOKEN) { throw 'Runner token changed on rerun.' }
    if ($first.N8N_ENCRYPTION_KEY -eq $first.N8N_RUNNERS_AUTH_TOKEN) { throw 'Secrets were reused.' }
    $runtimePath = Join-Path $testDirectory '.env.local'
    $originalText = [IO.File]::ReadAllText($runtimePath)
    if ($originalText.Contains('GENERATE_ON_FIRST_RUN')) { throw 'First-run placeholders remain.' }
    if ($first.N8N_ENCRYPTION_KEY -cnotmatch '^[a-f0-9]{64}$' -or $first.N8N_RUNNERS_AUTH_TOKEN -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid generated secrets.' }
    $existingText = $originalText.Replace($first.N8N_RUNNERS_AUTH_TOKEN, '"GENERATE_ON_FIRST_RUN"')
    $existingText += "`r`nN8N_EXTRA_TOKEN=GENERATE_ON_FIRST_RUN`r`nN8N_QUOTED_TOKEN='GENERATE_ON_FIRST_RUN'`r`nN8N_LITERAL=prefix_GENERATE_ON_FIRST_RUN`r`n# N8N_COMMENT=GENERATE_ON_FIRST_RUN`r`n"
    [IO.File]::WriteAllText($runtimePath, $existingText)
    $resolved = Initialize-LocalConfig $testDirectory
    if ($resolved.N8N_ENCRYPTION_KEY -cne $first.N8N_ENCRYPTION_KEY) { throw 'Existing encryption key was overwritten.' }
    foreach ($key in @('N8N_RUNNERS_AUTH_TOKEN', 'N8N_EXTRA_TOKEN', 'N8N_QUOTED_TOKEN')) {
        if ($resolved[$key] -cnotmatch '^[a-f0-9]{64}$') { throw "Unresolved existing-file placeholder: $key." }
    }
    if (@($resolved.N8N_RUNNERS_AUTH_TOKEN, $resolved.N8N_EXTRA_TOKEN, $resolved.N8N_QUOTED_TOKEN | Select-Object -Unique).Count -ne 3) { throw 'Generated tokens were reused.' }
    $resolvedText = [IO.File]::ReadAllText($runtimePath)
    if (-not $resolvedText.Contains('# N8N_COMMENT=GENERATE_ON_FIRST_RUN') -or $resolved.N8N_LITERAL -cne 'prefix_GENERATE_ON_FIRST_RUN') { throw 'Non-placeholder content changed.' }
    $null = Initialize-LocalConfig $testDirectory
    if ([IO.File]::ReadAllText($runtimePath) -cne $resolvedText) { throw 'Runtime file changed on rerun.' }
    foreach ($case in @(@('N8N_HOST', '0.0.0.0'), @('N8N_PORT', '65536'), @('N8N_DOCKER_CONTEXT', 'production'), @('N8N_VERSION', 'latest'), @('N8N_DOCKER_INSTALLER_URL_AMD64', 'https://example.com/installer.exe'))) {
        $bad = $first.Clone()
        $bad[$case[0]] = $case[1]
        $rejected = $false
        try { Assert-LocalConfig $bad } catch { $rejected = $true }
        if (-not $rejected) { throw ('Unsafe setting was accepted: ' + $case[0]) }
    }
    $quoted = Format-ProcessArguments @('-File', 'C:\User Files\n8n\n8n-docker-compose-deploy-win.ps1')
    if ($quoted -ne '"-File" "C:\User Files\n8n\n8n-docker-compose-deploy-win.ps1"') { throw 'Path quoting failed.' }
    $explanation = @(& { Write-LocalCommand -Command 'wsl.exe --version' -Purpose 'Check WSL compatibility before downloading anything.' } 6>&1)
    $explanationText = $explanation -join "`n"
    if (-not $explanationText.Contains('Goal: Check WSL compatibility before downloading anything.') -or -not $explanationText.Contains('RUN: wsl.exe --version') -or $explanationText.IndexOf('Goal:') -gt $explanationText.IndexOf('RUN:')) { throw 'Command explanation is missing or printed after the command.' }
    $wslText = "WSL version: 2.3.26.0`nKernel version: 5.15.167.4-1"
    $wslUtf16 = -join ($wslText.ToCharArray() | ForEach-Object { [string]$_ + [char]0 })
    if (-not (Test-LocalWslVersion $wslText) -or -not (Test-LocalWslVersion $wslUtf16)) { throw 'Supported WSL version triggered an unnecessary update.' }
    if ((Test-LocalWslVersion 'WSL version: 1.2.5.0') -or (Test-LocalWslVersion 'not installed')) { throw 'Unsupported WSL version was accepted.' }
    # A harmless child process verifies live output, heartbeat, final log draining and exit codes.
    $progressLog = Join-Path $testDirectory 'progress.log'
    [IO.File]::WriteAllText($progressLog, "previous run`n")
    $offset = [IO.File]::ReadAllText($progressLog).Length
    $childScript = @'
. '__SCRIPT__'
$script:PrerequisiteLogFile = '__LOG__'
Write-LocalProgress 'prerequisite stage started'
Start-Sleep -Seconds 2
Write-LocalProgress 'prerequisite stage finished'
exit 7
'@
    $childScript = $childScript.Replace('__LOG__', $progressLog.Replace("'", "''"))
    $childScript = $childScript.Replace('__SCRIPT__', (Join-Path $PSScriptRoot 'n8n-docker-compose-deploy-win.ps1').Replace("'", "''"))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    $powershell = Join-Path $PSHOME 'powershell.exe'
    Write-Host '+ Start-Process powershell.exe (harmless progress-display test)'
    $child = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) -WindowStyle Hidden -PassThru
    $events = @(& { Wait-LocalProcess -Process $child -Activity 'Progress test' -LogPath $progressLog -LogOffset $offset -HeartbeatSeconds 0.1 } 6>&1)
    $exitCode = $events[-1]
    $visible = ($events | Select-Object -SkipLast 1) -join "`n"
    if ($exitCode -ne 7) { throw 'Child failure exit code was lost.' }
    $writer = [IO.File]::Open($progressLog, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    try {
        $sharedText = Read-LocalProgressLog $progressLog
        if ($null -eq $sharedText -or -not $sharedText.Contains('prerequisite stage finished')) { throw 'Progress log could not be read while its writer held it open.' }
        $script:PrerequisiteLogFile = $progressLog
        $null = @(& { Write-LocalProgress 'Shared writer test' } 6>&1)
        $script:PrerequisiteLogFile = $null
        if (-not (Read-LocalProgressLog $progressLog).Contains('Shared writer test')) { throw 'Diagnostic output could not append to a shared log.' }
    } finally { $writer.Dispose() }
    $exclusive = [IO.File]::Open($progressLog, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if ($null -ne (Read-LocalProgressLog $progressLog)) { throw 'Exclusively locked log should be skipped for retry.' }
        $lockedEvents = @(& { Wait-LocalProcess -Process $child -Activity 'Locked-log final drain' -LogPath $progressLog } 6>&1)
        if ($lockedEvents[-1] -ne 7) { throw 'Locked log changed the child exit result.' }
    } finally { $exclusive.Dispose() }
    if ($null -ne (Read-LocalProgressLog (Join-Path $testDirectory 'not-created.log'))) { throw 'Missing log should be skipped for retry.' }
    $legacyLog = 'Start time: ' + (Get-Process -Id $PID).StartTime.ToString('yyyyMMddHHmmss') + "`nProcess ID: $PID"
    $rejectedLegacy = $false
    try { Assert-NoLegacyPrerequisiteProcess $legacyLog } catch { $rejectedLegacy = $_.Exception.Message.Contains('No second setup was started') }
    if (-not $rejectedLegacy) { throw 'Active legacy setup was not detected.' }
    $processFixture = @(
        [pscustomobject]@{ ProcessId=900001; ParentProcessId=900000; Name='powershell.exe'; CreationDate='2026-11-15 11:00:00'; CommandLine='powershell.exe -File "C:\User Files\n8n\n8n-docker-compose-deploy-win.ps1" -PrepareMachine' },
        [pscustomobject]@{ ProcessId=900002; ParentProcessId=900001; Name='wsl.exe'; CreationDate='2026-11-15 11:00:01'; CommandLine='wsl.exe --update --web-download' },
        [pscustomobject]@{ ProcessId=900003; ParentProcessId=900000; Name='wsl.exe'; CreationDate='2026-11-15 11:00:02'; CommandLine='unrelated distribution shell' }
    )
    $report = (@(& { Write-LocalSetupConflict -Processes $processFixture } 6>&1)) -join "`n"
    foreach ($detail in @('PID 900001', 'PID 900002', 'wsl.exe --update --web-download', 'C:\User Files\n8n\.local-prerequisites.log', 'Alt+Tab', 'Ctrl+Shift+Esc', 'Get-Content -LiteralPath', "& 'C:\User Files\n8n\n8n-docker-compose-deploy-win.cmd' status", "& 'C:\User Files\n8n\n8n-docker-compose-deploy-win.cmd' cancel")) {
        if (-not $report.Contains($detail)) { throw ('User conflict guidance is missing: ' + $detail) }
    }
    if ($report.Contains('unrelated distribution shell') -or $report.Contains('taskkill /PID 900003')) { throw 'Conflict report included an unrelated WSL process.' }
    if ($report.Contains('taskkill /PID')) { throw 'Conflict instructions still require copying a stale PID.' }
    $expectedScript = 'C:\User Files\n8n\n8n-docker-compose-deploy-win.ps1'
    $original = $processFixture[0]
    if (-not (Test-LocalSetupSnapshot $original $original $expectedScript)) { throw 'Valid live setup identity was rejected.' }
    if ((Test-LocalSetupSnapshot $original $null $expectedScript)) { throw 'Exited process was accepted for cancellation.' }
    $reused = $original | Select-Object *
    $reused.CreationDate = '2026-11-15 12:00:00'
    if ((Test-LocalSetupSnapshot $original $reused $expectedScript)) { throw 'Reused PID was accepted for cancellation.' }
    $foreign = $original | Select-Object *
    $foreign.CommandLine = 'powershell.exe -File "C:\Other User\n8n\n8n-docker-compose-deploy-win.ps1" -PrepareMachine'
    if ((Test-LocalSetupSnapshot $original $foreign $expectedScript)) { throw 'Setup from another directory was accepted for cancellation.' }
    $emptyReport = (@(& { Write-LocalSetupConflict -Processes @($processFixture[2]) -StatusOnly } 6>&1)) -join "`n"
    if (-not $emptyReport.Contains('No active n8n prerequisite setup was found NOW') -or $emptyReport.Contains('taskkill')) { throw 'No-process status instructions were misleading.' }
    foreach ($message in @('prerequisite stage started', 'prerequisite stage finished', 'Still working')) {
        if (-not $visible.Contains($message)) { throw ('Progress message missing: ' + $message) }
    }
    if ($visible.Contains('previous run')) { throw 'Stale prerequisite log was replayed.' }
    $startEvent = $events | Where-Object { $_ -is [Management.Automation.InformationRecord] -and $_.ToString().Contains('prerequisite stage started') } | Select-Object -First 1
    if (-not $startEvent -or $startEvent.TimeGenerated -ge $child.ExitTime.AddMilliseconds(-500)) { throw 'Prerequisite output was not visible while the child was still running.' }
    $events = @(& { Invoke-Native $powershell @('-NoProfile', '-NonInteractive', '-Command', "[Console]::WriteLine('native progress'); exit 9") -AllowFailure -StreamOutput } 6>&1)
    $nativeResult = $events[-1]
    if ($nativeResult.Code -ne 9 -or -not $nativeResult.Text.Contains('native progress') -or -not (($events | Select-Object -SkipLast 1) -join "`n").Contains('native progress')) { throw 'Native command output did not stream or its result changed.' }
    $consoleResult = Invoke-ConsoleCommand $powershell @('-NoProfile', '-NonInteractive', '-Command', "[Console]::WriteLine('Direct console output test'); exit 6")
    if ($consoleResult.Code -ne 6) { throw 'Direct-console command lost its exit code.' }
    $silentWait = @(& { Wait-LocalProcess -Process $child -Activity 'Native progress window' -HeartbeatSeconds 0 } 6>&1)
    if ((($silentWait | Select-Object -SkipLast 1) -join "`n").Contains('Still working')) { throw 'Timer messages remain enabled for native progress windows.' }
    $cli = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
    if (Test-Path -LiteralPath $cli) {
        $null = Invoke-Native $cli @('compose', '--env-file', (Join-Path $testDirectory '.env.local'), '--file', (Join-Path $PSScriptRoot 'n8n-compose-local.yaml'), 'config', '--quiet')
    }
    Write-Host 'Local launcher checks passed; no software installed and no containers started.'
} finally {
    # Restrict cleanup to the freshly created test directory under the system temp root.
    $resolved = [IO.Path]::GetFullPath($testDirectory)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'n8n-local-test-*') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
