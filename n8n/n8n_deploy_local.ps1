<#
Install/check Docker Desktop and deploy local n8n on Windows 11.
Run n8n_deploy_local.cmd, or: powershell -NoProfile -ExecutionPolicy Bypass -File .\n8n_deploy_local.ps1
Example: double-click n8n_deploy_local.cmd; the UI opens after readiness succeeds.
Settings/secrets are stored in .env.local. No server settings are loaded.
#>
[CmdletBinding()]
param([switch]$PrepareMachine, [switch]$SetupStatus, [switch]$CancelSetup, [switch]$DiagnosticsAdmin, [string]$DiagnosticsLogName)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LocalRoot = $PSScriptRoot
$script:PrerequisiteLogFile = $null
$script:LogWriteWarningShown = $false

function Write-LocalProgress {
    param([AllowEmptyString()][string]$Message)
    Write-Host $Message
    if ($script:PrerequisiteLogFile) {
        $stream = $null
        $writer = $null
        try {
            # Share writes with an older setup's transcript; flush each message for the parent console.
            $stream = [IO.File]::Open($script:PrerequisiteLogFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
            $null = $stream.Seek(0, [IO.SeekOrigin]::End)
            $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
            $writer.WriteLine($Message)
        } catch [IO.IOException] {
            if (-not $script:LogWriteWarningShown) {
                Write-Host ('Log is temporarily locked: ' + $script:PrerequisiteLogFile + '. Read the visible Administrator window for the full output.')
                $script:LogWriteWarningShown = $true
            }
        } finally {
            if ($writer) { $writer.Dispose() } elseif ($stream) { $stream.Dispose() }
        }
    }
}

function Write-LocalCommand {
    param([string]$Command, [string]$Purpose)
    Write-LocalProgress ''
    Write-LocalProgress ('Goal: ' + $Purpose)
    Write-LocalProgress ('RUN: ' + $Command)
}

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [switch]$AllowFailure, [switch]$StreamOutput, [string]$Purpose = 'Run the requested diagnostic command and check its result.')
    Write-LocalCommand -Command ('& "' + $File + '" ' + (Format-ProcessArguments $Arguments)) -Purpose $Purpose
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = New-Object 'System.Collections.Generic.List[string]'
        & $File @Arguments 2>&1 | ForEach-Object {
            # WSL can emit UTF-16 NULs when Windows PowerShell captures its output.
            $line = ([string]$_).Replace([string][char]0, '')
            $output.Add($line)
            if ($StreamOutput) { Write-LocalProgress $line }
        }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw (($output -join "`n") + "`nCommand failed with exit code $code.")
    }
    return [pscustomobject]@{ Code = $code; Text = ($output -join "`n") }
}

function Invoke-ConsoleCommand {
    param([string]$File, [string[]]$Arguments, [string]$Purpose = 'Run the command in the console so its native progress remains visible.')
    Write-LocalCommand -Command ('& "' + $File + '" ' + (Format-ProcessArguments $Arguments)) -Purpose $Purpose
    # Inherit the real console handles; no PowerShell pipe/capture that would hide native progress bars.
    $process = Start-Process -FilePath $File -ArgumentList (Format-ProcessArguments $Arguments) -NoNewWindow -Wait -PassThru
    return [pscustomobject]@{ Code = $process.ExitCode; Text = '' }
}

function Test-LocalWslVersion {
    param([string]$Text)
    $match = [regex]::Match($Text.Replace([string][char]0, ''), '\b(\d+\.\d+\.\d+(?:\.\d+)?)\b')
    return $match.Success -and [version]$match.Groups[1].Value -ge [version]'2.1.5'
}

function Read-LocalProgressLog {
    param([string]$Path)
    $stream = $null
    $reader = $null
    try {
        # Readers must allow the elevated writer's existing write handle as well as future writes.
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = [IO.StreamReader]::new($stream)
        return $reader.ReadToEnd()
    } catch [IO.IOException] {
        return $null
    } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}

function Assert-NoLegacyPrerequisiteProcess {
    param([string]$LogText)
    # Older launcher versions used a transcript and did not hold the new prerequisite mutex.
    $logMatches = [regex]::Matches($LogText, '(?ms)Start time: (\d{14}).*?Process ID: (\d+)')
    if ($logMatches.Count -eq 0) { return }
    $last = $logMatches[$logMatches.Count - 1]
    $oldId = [int]$last.Groups[2].Value
    $old = Get-Process -Id $oldId -ErrorAction SilentlyContinue
    if ($old -and $old.ProcessName -eq 'powershell' -and $old.StartTime.ToString('yyyyMMddHHmmss') -eq $last.Groups[1].Value) {
        Write-LocalSetupConflict -LegacyProcessId $oldId
        throw 'An older prerequisite setup is still running. No second setup was started. Use the process details and instructions printed above.'
    }
}

function Write-LocalSetupConflict {
    param([object[]]$Processes = @(), [int]$LegacyProcessId = 0, [switch]$StatusOnly)
    Write-LocalProgress ''
    Write-LocalProgress ('N8N SETUP PROCESS SNAPSHOT: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-LocalProgress 'This is a snapshot, not a permanent PID assignment. A process may exit after this check. Use the status/cancel commands below to query current processes again.'
    if (-not $Processes.Count) {
        Write-LocalCommand -Command 'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine' -Purpose 'Find the existing n8n setup and its child processes so you can see exactly what is still running.'
        $Processes = @(Get-CimInstance Win32_Process)
    }
    $owners = @($Processes | Where-Object {
        $_.ProcessId -ne $PID -and (
            ($LegacyProcessId -gt 0 -and $_.ProcessId -eq $LegacyProcessId) -or
            ($_.Name -in @('powershell.exe', 'pwsh.exe') -and $_.CommandLine -match '(?i)n8n_deploy_local\.ps1' -and $_.CommandLine -match '(?i)-PrepareMachine')
        )
    })
    if (-not $owners.Count) {
        if ($StatusOnly) {
            Write-LocalProgress 'No active n8n prerequisite setup was found NOW. A PID from an earlier message may already have exited.'
            Write-LocalProgress 'No processes were stopped. Start setup normally:'
            Write-LocalProgress ("   & '" + (Join-Path $script:LocalRoot 'n8n_deploy_local.cmd').Replace("'", "''") + "'")
            return
        }
        else { Write-LocalProgress 'The previous setup may have exited, or this account cannot read its details. Do not search for an old PID or terminate unrelated processes.' }
        Write-LocalProgress 'Refresh with administrator access (approve UAC); paste this command in your terminal:'
        Write-LocalProgress ("   & '" + (Join-Path $script:LocalRoot 'n8n_deploy_local.cmd').Replace("'", "''") + "' status")
        Write-LocalProgress 'If the administrator status check also finds no setup, run the launcher normally again.'
        return
    }
    foreach ($owner in $owners) {
        $ownerId = [int]$owner.ProcessId
        $title = ''
        try { $title = (Get-Process -Id $ownerId -ErrorAction Stop).MainWindowTitle } catch { }
        Write-LocalProgress ''
        Write-LocalProgress ("Existing setup: $($owner.Name), PID $ownerId, parent PID $($owner.ParentProcessId), started $($owner.CreationDate)")
        Write-LocalProgress ('Running command: ' + $owner.CommandLine)
        if ($title) { Write-LocalProgress ('Window title: ' + $title) }
        else { Write-LocalProgress 'Window title: not visible (this may be an older hidden setup). Use the log or Task Manager steps below.' }
        $scriptPath = Join-Path $script:LocalRoot 'n8n_deploy_local.ps1'
        $pathMatch = [regex]::Match([string]$owner.CommandLine, '(?i)-File\s+(?:"([^"]+)"|(\S+))')
        if ($pathMatch.Success) {
            $scriptPath = if ($pathMatch.Groups[1].Success) { $pathMatch.Groups[1].Value } else { $pathMatch.Groups[2].Value }
        }
        $directory = Split-Path $scriptPath
        $ownerLog = Join-Path $directory '.local-prerequisites.log'
        Write-LocalProgress ('Setup file: ' + $scriptPath)
        Write-LocalProgress ('Setup log: ' + $ownerLog)
        $queue = [Collections.Generic.Queue[int]]::new()
        $seen = @{}
        $queue.Enqueue($ownerId)
        while ($queue.Count) {
            $parentId = $queue.Dequeue()
            if ($seen.ContainsKey($parentId)) { continue }
            $seen[$parentId] = $true
            foreach ($child in @($Processes | Where-Object { $_.ParentProcessId -eq $parentId })) {
                Write-LocalProgress ("  Child process: $($child.Name), PID $($child.ProcessId), parent PID $parentId")
                Write-LocalProgress ('  Running command: ' + $child.CommandLine)
                $queue.Enqueue([int]$child.ProcessId)
            }
        }
        Write-LocalProgress ''
        Write-LocalProgress 'WHAT TO DO:'
        Write-LocalProgress '1. Obtain CURRENT process details with this command (it requests administrator access and does not install or stop anything):'
        Write-LocalProgress ("   & '" + (Join-Path $directory 'n8n_deploy_local.cmd').Replace("'", "''") + "' status")
        Write-LocalProgress '2. For a visible setup window press Alt+Tab and use the window title printed above. For Task Manager press Ctrl+Shift+Esc and select Details, not the grouped Processes tab shown by default. If the PID is absent, it has exited: refresh status instead of searching for that old number.'
        Write-LocalProgress '3. To watch the recorded setup commands: open Windows PowerShell and paste this line. Ctrl+C stops watching the log; it does not cancel setup:'
        Write-LocalProgress ("   Get-Content -LiteralPath '" + $ownerLog.Replace("'", "''") + "' -Tail 20 -Wait")
        Write-LocalProgress '4. To CANCEL setup from this directory, run the following command and approve UAC. It discovers and rechecks live processes; no PID needs to be copied:'
        Write-LocalProgress ("   & '" + (Join-Path $directory 'n8n_deploy_local.cmd').Replace("'", "''") + "' cancel")
        Write-LocalProgress '   Cancellation interrupts Windows/WSL setup and its children. It does not delete n8n workflows or Docker volumes. If setup has already exited, cancellation does nothing.'
        Write-LocalProgress '5. After that process has exited, start this launcher again:'
        Write-LocalProgress ("   & '" + (Join-Path $directory 'n8n_deploy_local.cmd').Replace("'", "''") + "'")
    }
}

function Test-LocalSetupIdentity {
    param([object]$Process, [string]$ExpectedScript)
    if ($Process.Name -notin @('powershell.exe', 'pwsh.exe') -or $Process.CommandLine -notmatch '(?i)-PrepareMachine(?:\s|$)') { return $false }
    $pathMatch = [regex]::Match([string]$Process.CommandLine, '(?i)-File\s+(?:"([^"]+)"|(\S+))')
    if (-not $pathMatch.Success) { return $false }
    $path = if ($pathMatch.Groups[1].Success) { $pathMatch.Groups[1].Value } else { $pathMatch.Groups[2].Value }
    return [string]::Equals([IO.Path]::GetFullPath($path), [IO.Path]::GetFullPath($ExpectedScript), [StringComparison]::OrdinalIgnoreCase)
}

function Test-LocalSetupSnapshot {
    param([object]$Original, [object]$Fresh, [string]$ExpectedScript)
    return $null -ne $Fresh -and $Fresh.ProcessId -eq $Original.ProcessId -and $Fresh.CreationDate -eq $Original.CreationDate -and (Test-LocalSetupIdentity $Fresh $ExpectedScript)
}

function Invoke-LocalSetupDiagnostics {
    param([switch]$Cancel)
    Write-LocalCommand -Command 'Get-CimInstance Win32_Process' -Purpose 'Query live setup processes now, with administrator access; do not reuse a PID from an earlier log.'
    $processes = @(Get-CimInstance Win32_Process)
    Write-LocalSetupConflict -Processes $processes -StatusOnly
    if (-not $Cancel) { return }
    $expectedScript = Join-Path $script:LocalRoot 'n8n_deploy_local.ps1'
    $owners = @($processes | Where-Object { $_.ProcessId -ne $PID -and (Test-LocalSetupIdentity $_ $expectedScript) })
    if (-not $owners.Count) {
        Write-LocalProgress 'Nothing to cancel: no active prerequisite setup from THIS directory exists. No processes were stopped. Run n8n_deploy_local.cmd normally.'
        return
    }
    foreach ($owner in $owners) {
        $ownerId = [int]$owner.ProcessId
        # Refresh identity immediately before cancellation to reject exited/reused PIDs and other copies.
        $fresh = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId"
        if (-not (Test-LocalSetupSnapshot $owner $fresh $expectedScript)) {
            Write-LocalProgress ("Setup PID $ownerId exited or changed identity. It was not stopped.")
            continue
        }
        $result = Invoke-Native 'taskkill.exe' @('/PID', [string]$ownerId, '/T', '/F') -AllowFailure -StreamOutput -Purpose 'Cancel only this verified n8n prerequisite setup and its children; leave unrelated PowerShell/WSL processes untouched.'
        if ($result.Code -ne 0) {
            $remaining = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId"
            if ($remaining -and (Test-LocalSetupIdentity $remaining $expectedScript)) { throw 'Cancellation failed. The process is still running; the command output above explains the failure.' }
        }
    }
    Write-LocalProgress 'Cancellation check complete. Run n8n_deploy_local.cmd normally to start again.'
}

function Start-LocalSetupDiagnostics {
    param([switch]$Cancel)
    $logName = '.local-setup-diagnostics-' + [guid]::NewGuid().ToString('N') + '.log'
    $logPath = Join-Path $script:LocalRoot $logName
    $mode = if ($Cancel) { '-CancelSetup' } else { '-SetupStatus' }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $arguments = Format-ProcessArguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:LocalRoot 'n8n_deploy_local.ps1'), $mode, '-DiagnosticsAdmin', '-DiagnosticsLogName', $logName)
    Write-LocalCommand -Command ('Start-Process powershell.exe -Verb RunAs ' + $mode) -Purpose 'Request administrator access to inspect live setup processes. Results appear in this original console; no Windows components are installed.'
    $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Normal -PassThru
    $code = Wait-LocalProcess -Process $process -Activity 'Current setup diagnostics' -LogPath $logPath -HeartbeatSeconds 0
    if ($code -ne 0) { throw 'Setup diagnostics failed; read the detailed output above.' }
}

function Wait-LocalProcess {
    param(
        [Diagnostics.Process]$Process,
        [string]$Activity,
        [string]$LogPath = '',
        [int]$LogOffset = 0,
        [double]$HeartbeatSeconds = 10
    )
    $started = [DateTime]::UtcNow
    $nextHeartbeat = $started.AddSeconds($HeartbeatSeconds)
    Write-Host ($Activity + ' is running. Progress appears below.')
    if ($LogPath) { Write-Host ('Log: ' + $LogPath) }
    do {
        if ($LogPath) {
            $text = Read-LocalProgressLog $LogPath
            if ($null -ne $text) {
                if ($text.Length -lt $LogOffset) { $LogOffset = 0 }
                if ($text.Length -gt $LogOffset) {
                    Write-Host $text.Substring($LogOffset) -NoNewline
                    $LogOffset = $text.Length
            }
                }
        }
        if ($Process.HasExited) { break }
        if ($HeartbeatSeconds -gt 0 -and [DateTime]::UtcNow -ge $nextHeartbeat) {
            $elapsed = [int]([DateTime]::UtcNow - $started).TotalSeconds
            Write-Host ("[$Activity] Still working ($elapsed seconds elapsed). Windows operations can take several minutes.")
            $nextHeartbeat = [DateTime]::UtcNow.AddSeconds($HeartbeatSeconds)
        }
        $null = $Process.WaitForExit(250)
    } while ($true)
    # A process can finish between reading its log and checking HasExited; drain the final output.
    $Process.WaitForExit()
    if ($LogPath) {
        $text = Read-LocalProgressLog $LogPath
        if ($null -ne $text -and $text.Length -gt $LogOffset) { Write-Host $text.Substring($LogOffset) -NoNewline }
    }
    Write-Host ("$Activity finished with exit code $($Process.ExitCode).")
    return $Process.ExitCode
}

function Read-LocalConfig {
    param([string]$Path)
    $config = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        $parts = $line.Split([char[]]'=', [int]2)
        if ($parts.Count -ne 2 -or $parts[0] -notmatch '^N8N_[A-Z0-9_]+$') { throw 'Invalid .env.local entry.' }
        $config[$parts[0]] = $parts[1].Trim().Trim([char]34, [char]39)
    }
    return $config
}

function Assert-LocalConfig {
    param([hashtable]$Config)
    if ($Config.N8N_HOST -ne '127.0.0.1') { throw 'N8N_HOST must be 127.0.0.1; this User deployment stays on this PC.' }
    if ($Config.N8N_PROJECT_NAME -notmatch '^[a-z0-9][a-z0-9_-]+$') { throw 'Invalid N8N_PROJECT_NAME.' }
    foreach ($key in @('N8N_PORT', 'N8N_DOCKER_TIMEOUT_SECONDS', 'N8N_STARTUP_TIMEOUT_SECONDS', 'N8N_MIN_WINDOWS_BUILD')) {
        $number = 0
        if (-not [int]::TryParse($Config[$key], [ref]$number) -or $number -lt 1) { throw "Invalid $key." }
        if ($key -eq 'N8N_PORT' -and $number -gt 65535) { throw 'Invalid N8N_PORT.' }
    }
    if ($Config.N8N_OPEN_BROWSER -notin @('true', 'false')) { throw 'N8N_OPEN_BROWSER must be true or false.' }
    if ($Config.N8N_DOCKER_CONTEXT -ne 'desktop-linux') { throw 'N8N_DOCKER_CONTEXT must be desktop-linux to avoid deploying to a remote server.' }
    if ($Config.N8N_VERSION -notmatch '^\d+\.\d+\.\d+$') { throw 'Use an exact N8N_VERSION, for example 2.47.7.' }
    foreach ($key in @('N8N_DOCKER_INSTALLER_URL_AMD64', 'N8N_DOCKER_INSTALLER_URL_ARM64')) {
        $uri = [uri]$Config[$key]
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'desktop.docker.com') { throw "$key must use Docker's official HTTPS download host." }
    }
}

function Initialize-LocalConfig {
    param([string]$Directory)
    $path = Join-Path $Directory '.env.local'
    if (-not (Test-Path -LiteralPath $path)) { Copy-Item -LiteralPath (Join-Path $Directory '.env.local.example') -Destination $path }
    $text = [IO.File]::ReadAllText($path)
    # Resolve every exact placeholder, including in an existing runtime file.
    $pattern = '(?m)^(?<prefix>N8N_[A-Z0-9_]+=[ \t]*)(?<value>GENERATE_ON_FIRST_RUN|"GENERATE_ON_FIRST_RUN"|''GENERATE_ON_FIRST_RUN'')(?<suffix>[ \t]*)(?=\r?$)'
    $updated = [regex]::Replace($text, $pattern, [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $secret = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        return $match.Groups['prefix'].Value + $secret + $match.Groups['suffix'].Value
    })
    if ($updated -cne $text) {
        [IO.File]::WriteAllText($path, $updated, (New-Object Text.UTF8Encoding($false)))
    }
    $config = Read-LocalConfig $path
    Assert-LocalConfig $config
    foreach ($key in @('N8N_ENCRYPTION_KEY', 'N8N_RUNNERS_AUTH_TOKEN')) {
        if ($config[$key] -notmatch '^[a-f0-9]{64}$') { throw "Invalid $key; preserve the original generated key for an existing installation." }
    }
    return $config
}

function Get-DesktopPath {
    foreach ($path in @((Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'))) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Format-ProcessArguments {
    param([string[]]$Values)
    return (($Values | ForEach-Object { '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }) -join ' ')
}

function Enable-LocalPrerequisites {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Windows prerequisite preparation requires administrator approval.' }
    $restart = $false
    foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
        Write-LocalCommand -Command "Get-WindowsOptionalFeature -Online -FeatureName $feature" -Purpose 'Check whether this Windows component required by the WSL 2 Linux backend is enabled.'
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature
        Write-LocalProgress ("Windows feature ${feature}: $($state.State)")
        if ($state.State -ne 'Enabled') {
            Write-LocalCommand -Command "Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart" -Purpose 'Enable the missing Windows component. Do not restart automatically; let the User save their work first.'
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
            $restart = $restart -or $result.RestartNeeded -or ($state.State -eq 'EnablePending')
        }
    }
    if ($restart) { return 3010 }
    $version = Invoke-Native 'wsl.exe' @('--version') -AllowFailure -StreamOutput -Purpose 'Read the installed WSL version. A supported version is reused without downloading an update.'
    if ($version.Code -eq 0 -and (Test-LocalWslVersion $version.Text)) {
        Write-LocalProgress 'Installed WSL meets the minimum version. Skipping WSL update.'
        return 0
    }
    if ($version.Code -ne 0) {
        $result = Invoke-ConsoleCommand 'wsl.exe' @('--install', '--no-distribution', '--web-download') -Purpose 'Install the WSL runtime that Docker uses to run Linux containers. No separate Ubuntu distribution is needed.'
    } else {
        $result = Invoke-ConsoleCommand 'wsl.exe' @('--update', '--web-download') -Purpose 'Update an older WSL runtime to support Docker Desktop. WSL displays its own download and installation progress here.'
    }
    if ($result.Code -in @(3010, 1641)) { return 3010 }
    if ($result.Code -ne 0) { throw 'WSL setup failed. Check Windows Update/network policy and rerun the launcher.' }
    return 0
}

function Register-LocalResume {
    $launcher = Join-Path $script:LocalRoot 'n8n_deploy_local.cmd'
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $resumeCommand = '"' + $env:ComSpec + '" /c ""' + $launcher + '""'
    if (-not (Test-Path $key)) {
        Write-LocalCommand -Command "New-Item -Path '$key' -Force" -Purpose 'Create the current user''s one-time startup registry key when it is missing.'
        New-Item -Path $key -Force | Out-Null
    }
    Write-LocalCommand -Command ("New-ItemProperty -Path '{0}' -Name LocalN8nDeployResume -Value '{1}' -PropertyType String -Force" -f $key, $resumeCommand.Replace("'", "''")) -Purpose 'Register one continuation of this launcher after your next Windows login, so setup can resume after a required restart.'
    New-ItemProperty -Path $key -Name 'LocalN8nDeployResume' -Value $resumeCommand -PropertyType String -Force | Out-Null
    Write-Host 'Windows restart required. Save your work and restart Windows. Setup will continue once after your next login.'
}

function Start-LocalDeployment {
    $config = Initialize-LocalConfig $script:LocalRoot
    if ([Environment]::OSVersion.Version.Build -lt [int]$config.N8N_MIN_WINDOWS_BUILD) { throw 'Update Windows 11 to a Docker-supported release before running this launcher.' }
    Write-LocalCommand -Command 'Get-CimInstance Win32_ComputerSystem' -Purpose 'Read installed RAM and check whether the Windows hypervisor is available for Docker Linux containers.'
    $system = Get-CimInstance Win32_ComputerSystem
    if ([double]$system.TotalPhysicalMemory -lt 7.5GB) { throw 'Docker Desktop requires at least 8 GB of system RAM.' }
    Write-LocalCommand -Command 'Get-CimInstance Win32_Processor | Select-Object -First 1' -Purpose 'Check CPU virtualization support. If it is disabled in BIOS/UEFI, Docker cannot start its Linux backend.'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if (-not $system.HypervisorPresent -and -not $cpu.VirtualizationFirmwareEnabled) { throw 'Enable CPU virtualization in BIOS/UEFI, then rerun this launcher. Windows cannot enable that firmware setting automatically.' }
    $desktop = Get-DesktopPath
    $cli = if ($desktop) { Join-Path (Split-Path $desktop) 'resources\bin\docker.exe' } else { $null }
    $ready = $false
    if ($cli -and (Test-Path -LiteralPath $cli)) {
        $check = Invoke-Native $cli @('--context', $config.N8N_DOCKER_CONTEXT, 'info', '--format', '{{.OSType}}') -AllowFailure -Purpose 'Check whether the local Docker Desktop engine is already running Linux containers. A ready engine skips prerequisite setup.'
        $ready = $check.Code -eq 0 -and $check.Text.Trim() -eq 'linux'
    }
    if (-not $ready) {
        $powershell = Join-Path $PSHOME 'powershell.exe'
        $arguments = Format-ProcessArguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-PrepareMachine')
        $logPath = Join-Path $script:LocalRoot '.local-prerequisites.log'
        $previousLog = Read-LocalProgressLog $logPath
        if ($null -ne $previousLog) { Assert-NoLegacyPrerequisiteProcess $previousLog }
        $logOffset = if ($null -ne $previousLog) { $previousLog.Length } else { 0 }
        Write-LocalCommand -Command ('Start-Process -FilePath "' + $powershell + '" -ArgumentList ' + "'" + $arguments.Replace("'", "''") + "'" + ' -Verb RunAs -WindowStyle Normal -PassThru') -Purpose 'Open an Administrator PowerShell window to check or enable Windows/WSL components. Approve the UAC prompt; native progress appears in that window.'
        Write-Host 'Watch the separate Administrator window for Windows/WSL progress and the native download percentage.'
        $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Normal -PassThru
        $exitCode = Wait-LocalProcess -Process $process -Activity 'Windows/WSL setup (Administrator window)' -LogPath $logPath -LogOffset $logOffset -HeartbeatSeconds 0
        if ($exitCode -eq 3010) { Register-LocalResume; return }
        if ($exitCode -ne 0) { throw 'Prerequisite setup failed. See the output above and .local-prerequisites.log in this directory.' }
    }
    if (-not $desktop) {
        $arch = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')
        $downloadKey = if ($arch -eq 'ARM64') { 'N8N_DOCKER_INSTALLER_URL_ARM64' } else { 'N8N_DOCKER_INSTALLER_URL_AMD64' }
        $installer = Join-Path $env:TEMP ('n8n-docker-installer-' + [guid]::NewGuid().ToString('N') + '.exe')
        Write-LocalCommand -Command ('Invoke-WebRequest -Uri "' + $config[$downloadKey] + '" -OutFile "' + $installer + '" -UseBasicParsing') -Purpose 'Download the Docker Desktop installer from Docker''s official website because Docker Desktop was not found on this PC.'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $config[$downloadKey] -OutFile $installer -UseBasicParsing
        Write-LocalCommand -Command ('Get-AuthenticodeSignature -LiteralPath "' + $installer + '"') -Purpose 'Verify that the downloaded installer has a valid Docker publisher signature before executing it.'
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Docker') { throw 'Docker installer signature verification failed; installer was not executed.' }
        Write-LocalCommand -Command ('Start-Process -FilePath "' + $installer + '" -ArgumentList @(''install'', ''--user'', ''--backend=wsl-2'') -WindowStyle Normal -PassThru') -Purpose 'Install Docker Desktop for the current User account using the WSL 2 backend. The installer window shows actual progress.'
        Write-Host 'Watch the Docker Desktop installer window for installation progress.'
        $process = Start-Process -FilePath $installer -ArgumentList @('install', '--user', '--backend=wsl-2') -PassThru -WindowStyle Normal
        $exitCode = Wait-LocalProcess -Process $process -Activity 'Docker Desktop installation (installer window)' -HeartbeatSeconds 0
        if ($exitCode -in @(3010, 1641)) { Register-LocalResume; return }
        if ($exitCode -ne 0) { throw "Docker Desktop installer failed: $exitCode." }
        $desktop = Get-DesktopPath
        if (-not $desktop) { throw 'Docker Desktop executable was not found after installation.' }
        $cli = Join-Path (Split-Path $desktop) 'resources\bin\docker.exe'
    }
    if (-not $ready) {
        Write-LocalCommand -Command ('Start-Process -FilePath "' + $desktop + '"') -Purpose 'Start Docker Desktop. Its Linux engine must be ready before n8n containers can run.'
        Start-Process -FilePath $desktop | Out-Null
        Write-Host 'Waiting for Docker Desktop. Accept its first-run agreement in the Docker window if prompted.'
        $deadline = [DateTime]::UtcNow.AddSeconds([int]$config.N8N_DOCKER_TIMEOUT_SECONDS)
        do {
            $check = Invoke-Native $cli @('--context', $config.N8N_DOCKER_CONTEXT, 'info', '--format', '{{.OSType}}') -AllowFailure -Purpose 'Poll Docker readiness. Expected result: linux. While it starts, complete any agreement shown in the Docker Desktop window.'
            if ($check.Code -eq 0 -and $check.Text.Trim() -eq 'linux') { $ready = $true; break }
            Start-Sleep -Seconds 5
        } while ([DateTime]::UtcNow -lt $deadline)
        if (-not $ready) { throw 'Docker Linux engine is not ready. Complete Docker Desktop onboarding and rerun this launcher. Windows containers mode is not supported.' }
    }
    # Make the validated file authoritative over inherited N8N_* environment values.
    foreach ($key in $config.Keys) { [Environment]::SetEnvironmentVariable($key, $config[$key], 'Process') }
    $compose = @('--context', $config.N8N_DOCKER_CONTEXT, 'compose', '--project-name', $config.N8N_PROJECT_NAME, '--env-file', (Join-Path $script:LocalRoot '.env.local'), '--file', (Join-Path $script:LocalRoot 'n8n_compose_local.yaml'))
    $null = Invoke-Native $cli ($compose + @('config', '--quiet')) -Purpose 'Validate n8n_compose_local.yaml with .env.local without printing rendered passwords or tokens. No containers are started by this check.'
    $result = Invoke-ConsoleCommand $cli ($compose + @('up', '-d', '--wait', '--wait-timeout', $config.N8N_STARTUP_TIMEOUT_SECONDS)) -Purpose 'Download missing images, create or reuse the persistent data volume, start n8n and its Code-node runner, and wait for n8n readiness. Existing User data is preserved.'
    if ($result.Code -ne 0) {
        $logs = Invoke-Native $cli ($compose + @('logs', '--tail', '60')) -AllowFailure -Purpose 'Display recent container logs to explain why n8n or its runner failed to start.'
        Write-Host $logs.Text
        throw 'Local n8n did not start. Check the error above; a port conflict can be resolved by changing N8N_PORT in .env.local.'
    }
    $url = 'http://localhost:' + $config.N8N_PORT + '/'
    $healthUrl = $url + 'healthz/readiness'
    Write-LocalCommand -Command ('Invoke-WebRequest -Uri "' + $healthUrl + '" -UseBasicParsing -TimeoutSec 15') -Purpose 'Make an HTTP request to n8n''s readiness endpoint. A successful response confirms that the application can serve requests.'
    $null = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 15
    Write-Host "`nLocal n8n is ready. Open: $url"
    Write-Host 'Create your owner account in the browser. Data is preserved when you rerun this launcher.'
    if ($config.N8N_OPEN_BROWSER -eq 'true') {
        Write-LocalCommand -Command ('Start-Process "' + $url + '"') -Purpose 'Open the local n8n UI in the default browser. On first launch, create your owner account there.'
        Start-Process $url | Out-Null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($SetupStatus -or $CancelSetup) {
            if ($DiagnosticsAdmin) {
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = New-Object Security.Principal.WindowsPrincipal($identity)
                if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator diagnostics require UAC approval. Run n8n_deploy_local.cmd status or n8n_deploy_local.cmd cancel normally.' }
                if ($DiagnosticsLogName -notmatch '^\.local-setup-diagnostics-[a-f0-9]{32}\.log$') { throw 'Invalid diagnostics log name.' }
                $script:PrerequisiteLogFile = Join-Path $script:LocalRoot $DiagnosticsLogName
                Invoke-LocalSetupDiagnostics -Cancel:$CancelSetup
            } else { Start-LocalSetupDiagnostics -Cancel:$CancelSetup }
            exit 0
        }
        if ($PrepareMachine) {
            $setupLock = [Threading.Mutex]::new($false, 'Global\UserN8nPrerequisiteSetup')
            $ownsSetupLock = $false
            $script:PrerequisiteLogFile = Join-Path $script:LocalRoot '.local-prerequisites.log'
            try {
                try { $ownsSetupLock = $setupLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsSetupLock = $true }
                if (-not $ownsSetupLock) {
                    Write-LocalSetupConflict
                    throw 'Another prerequisite setup is running. Use the PID, window, log and cancellation instructions printed above.'
                }
                $windowTitle = "n8n setup - Administrator - PID $PID"
                try { $Host.UI.RawUI.WindowTitle = $windowTitle } catch { }
                Write-LocalProgress ('Administrator window title: ' + $windowTitle)
                Write-LocalProgress ("Setup process PID: $PID")
                Write-LocalProgress ('Setup file: ' + $PSCommandPath)
                Write-LocalProgress ('Live log: ' + $script:PrerequisiteLogFile)
                Write-LocalProgress 'Administrator access granted. Checking Windows features and WSL.'
                $result = Enable-LocalPrerequisites
            } catch {
                Write-LocalProgress ('ERROR: ' + $_.Exception.Message)
                $result = 1
            } finally {
                $script:PrerequisiteLogFile = $null
                if ($ownsSetupLock) { $setupLock.ReleaseMutex() }
                $setupLock.Dispose()
            }
            exit $result
        }
        Start-LocalDeployment
        exit 0
    } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
