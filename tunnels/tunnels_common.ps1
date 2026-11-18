<#
.SYNOPSIS
Shared tunnel checks and process supervision. Import from a tunnels_start_* script.
.DESCRIPTION
No server is started, no webhook POST is sent, and no application settings are changed.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TunnelMessage {
    param([string]$Level, [string]$Message)
    Write-Host "[$Level] $Message"
}

function Assert-TunnelInput {
    param([int]$Port, [string]$WebhookPath, [string]$LocalHost, [string]$HealthPath)
    if ($Port -lt 1 -or $Port -gt 65535) { throw 'Порт должен быть от 1 до 65535.' }
    foreach ($path in @($WebhookPath, $HealthPath)) {
        if ([string]::IsNullOrWhiteSpace($path) -or $path -notmatch '^/(?!/)' -or
            $path -match '[\p{Cc}\s\\#]' -or $path -match '(?i)%0[ad]') {
            throw 'Путь должен начинаться с одного /, без пробелов, #, обратных слешей и управляющих символов. Query string разрешён.'
        }
    }
    # Deliberately limit publication to loopback, including IPv6.
    if ($LocalHost -notin @('127.0.0.1', 'localhost', '::1')) {
        throw 'LocalHost: разрешены только 127.0.0.1, localhost и ::1.'
    }
}

function Get-TunnelOrigin {
    param([string]$LocalHost, [int]$Port)
    $address = $LocalHost
    if ($address -eq '::1') { $address = '[::1]' }
    return "http://${address}:$Port"
}

function Test-TunnelTcp {
    param([string]$LocalHost, [int]$Port)
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $task = $tcp.ConnectAsync($LocalHost, $Port)
        return ($task.Wait(2000) -and $tcp.Connected)
    } catch { return $false } finally { $tcp.Dispose() }
}

function Get-TunnelHttpStatus {
    param([string]$Url)
    # Do not follow redirects to other hosts, send credentials, or execute webhook POST.
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 5000
    $request.ReadWriteTimeout = 5000
    $request.Proxy = $null
    $response = $null
    try {
        $response = $request.GetResponse()
        return [int]$response.StatusCode
    } catch [Net.WebException] {
        $response = $_.Exception.Response
        if ($null -ne $response) { return [int]$response.StatusCode }
        return 0
    } finally { if ($null -ne $response) { $response.Close() } }
}

function Assert-TunnelServer {
    param([string]$LocalHost, [int]$Port, [string]$Origin, [string]$HealthPath)
    Write-TunnelMessage CHECK "Проверяю TCP ${LocalHost}:$Port и HTTP $HealthPath..."
    if (-not (Test-TunnelTcp $LocalHost $Port)) {
        throw "Локальный сервер недоступен: $Origin. Запустите приложение, проверьте порт и повторите запуск."
    }
    $status = Get-TunnelHttpStatus ($Origin + $HealthPath)
    if ($status -eq 0) { throw 'TCP доступен, но HTTP не отвечает. Проверьте, что приложение использует HTTP, и укажите правильный порт.' }
    Write-TunnelMessage OK "Локальный HTTP-сервер отвечает: HTTP $status. Это не проверка webhook POST."
}

function Get-TunnelPublicUrl {
    param([string]$Text, [string]$Provider)
    $pattern = switch ($Provider) {
        'cloudflare' { 'https://[a-z0-9-]+\.trycloudflare\.com' }
        'localtunnel' { 'https://[a-z0-9-]+\.loca\.lt' }
        'ngrok' { 'https://[a-z0-9.-]+\.(?:ngrok-free\.app|ngrok\.app|ngrok\.io|ngrok-free\.dev)' }
    }
    $match = [regex]::Match($Text, $pattern + '(?![a-zA-Z0-9.:-])')
    if (-not $match.Success) { return $null }
    $uri = $null
    if ([uri]::TryCreate($match.Value, [UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -eq 'https' -and $uri.HostNameType -eq 'Dns' -and $uri.IsDefaultPort) {
        return $uri.GetLeftPart([UriPartial]::Authority)
    }
    return $null
}

function Join-TunnelWebhook {
    param([string]$PublicUrl, [string]$WebhookPath)
    return $PublicUrl.TrimEnd('/') + $WebhookPath
}

function Get-TunnelFailure {
    param([string]$Text)
    if ($Text -match 'ERR_NGROK_108|ERR_NGROK_324|ERR_NGROK_727|limit|too many') {
        return 'Ограничение аккаунта/провайдера. Проверьте dashboard или выберите Cloudflare/localtunnel; лимиты не обходятся.'
    }
    if ($Text -match 'ERR_NGROK_4018|ERR_NGROK_105|ERR_NGROK_107|authenticat|authtoken') {
        return 'Ошибка авторизации ngrok. Нужен authtoken, а не API key: https://dashboard.ngrok.com/get-started/your-authtoken'
    }
    if ($Text -match 'EADDRINUSE|address already in use') { return 'Служебный порт занят. Повторите запуск с другим -NgrokApiPort.' }
    if ($Text -match 'unknown.*yes|unsupported.*option') { return 'Обновите Node.js LTS/npm: установленный npx не поддерживает --yes.' }
    return 'Клиент завершился или не выдал URL вовремя. Проверьте DNS, TLS, proxy/VPN, firewall и доступность провайдера; попробуйте другой туннель.'
}

function Get-TunnelCommand {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return $command.Source }
    return $null
}

function Request-TunnelInstall {
    param([switch]$InstallIfMissing, [string]$Name)
    if ($InstallIfMissing) { return }
    if ((Read-Host "$Name отсутствует. Установить из официального пакета winget? [Y/N]") -notmatch '^(?i:y|yes)$') {
        throw 'Установка отменена. Установите клиент вручную и повторите запуск.'
    }
}

function Install-TunnelTool {
    param([string]$Package, [string]$DownloadUrl, [switch]$InstallIfMissing)
    Request-TunnelInstall -InstallIfMissing:$InstallIfMissing -Name $Package
    $winget = Get-TunnelCommand 'winget.exe'
    if (-not $winget) {
        throw "winget не найден. Скачайте официальный пакет для архитектуры вашей Windows: $DownloadUrl . Распакуйте portable-клиент в пользовательскую папку и добавьте её в PATH. Для Node.js используйте официальный Windows zip."
    }
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    Write-TunnelMessage INFO "Архитектура Windows: $architecture. winget проверяет хеш пакета; обход проверки отключён."
    Write-Host "Goal: Установить $Package для текущего пользователя без повышения прав"
    Write-Host "RUN: winget install --id $Package --exact --source winget --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity"
    & $winget install --id $Package --exact --source winget --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "Установка не выполнена. Возможно, пакет не поддерживает --scope user. Альтернатива без UAC: официальный portable/zip из $DownloadUrl . Добавьте каталог в PATH; не меняйте Execution Policy."
    }
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function New-TunnelClient {
    param([string]$Executable, [string[]]$Arguments, [hashtable]$Environment = @{})
    if (-not ('InfrastructureTunnels.Client' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'tunnels_process.cs')
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    # All inputs are argument values, never PowerShell/cmd expressions.
    $quoted = foreach ($argument in $Arguments) {
        '"' + [regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
    }
    $info.Arguments = $quoted -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) { $info.EnvironmentVariables[$key] = $Environment[$key] }
    # Secret values are never part of the displayed command or command line.
    Write-Host 'Goal: Запустить клиент туннеля (секреты передаются только через окружение)'
    Write-Host ('RUN: "{0}" {1}' -f $Executable, $info.Arguments)
    return New-Object InfrastructureTunnels.Client($info)
}

function Get-TunnelNgrokUrl {
    param([int]$ApiPort, [string]$Origin, [int]$OwnedProcessId = 0)
    try {
        if ($OwnedProcessId -gt 0) {
            $listeners = @(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $ApiPort -State Listen -ErrorAction Stop)
            if (-not ($listeners | Where-Object { $_.OwningProcess -eq $OwnedProcessId })) { return $null }
        }
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/api/tunnels" -TimeoutSec 2
        foreach ($tunnel in $response.tunnels) {
            if ($tunnel.config.addr.TrimEnd('/') -eq $Origin) {
                $uri = $null
                $value = [string]$tunnel.public_url
                # The owned local API also supports ngrok custom domains.
                if ($value -notmatch '[\p{Cc}\s]' -and [uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -and
                    $uri.Scheme -eq 'https' -and $uri.HostNameType -eq 'Dns' -and
                    -not $uri.UserInfo -and $uri.IsDefaultPort -and $uri.AbsolutePath -eq '/' -and -not $uri.Query -and -not $uri.Fragment) {
                    return $uri.GetLeftPart([UriPartial]::Authority)
                }
            }
        }
    } catch { return $null }
    return $null
}

function Wait-TunnelUrl {
    param($Client, [string]$Provider, [int]$TimeoutSeconds, [int]$ApiPort, [string]$Origin, [switch]$VerboseOutput)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $diagnostic = ''
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $line = $Client.ReadLine()
        while ($null -ne $line) {
            # Raw CLI output can contain credentials; never echo or persist it.
            $diagnostic = ($diagnostic + "`n" + $line)
            if ($diagnostic.Length -gt 16384) { $diagnostic = $diagnostic.Substring($diagnostic.Length - 16384) }
            if ($VerboseOutput) {
                $code = [regex]::Match($line, 'ERR_NGROK_\d+')
                if ($code.Success) { Write-TunnelMessage WARN $code.Value }
            }
            if ($Provider -ne 'ngrok') {
                $url = Get-TunnelPublicUrl $line $Provider
                if ($url) { return $url }
            }
            $line = $Client.ReadLine()
        }
        if ($Client.Process.HasExited) { throw (Get-TunnelFailure $diagnostic) }
        if ($Provider -eq 'ngrok') {
            $url = Get-TunnelNgrokUrl $ApiPort $Origin $Client.Process.Id
            if ($url) { return $url }
        }
        Start-Sleep -Milliseconds 200
    }
    throw ("Таймаут ожидания HTTPS URL ($TimeoutSeconds сек). " + (Get-TunnelFailure $diagnostic))
}

function Start-TunnelSession {
    param([string]$Provider, [int]$Port, [string]$WebhookPath, [string]$LocalHost,
        [switch]$InstallIfMissing, [switch]$SkipPublicCheck, [switch]$VerboseOutput,
        [string]$HealthPath = '/', [int]$StartupTimeoutSeconds = 90, [int]$NgrokApiPort = 0,
        [string]$NgrokConfig = '')
    Assert-TunnelInput $Port $WebhookPath $LocalHost $HealthPath
    if ($NgrokConfig -and (-not (Test-Path -LiteralPath $NgrokConfig -PathType Leaf) -or $NgrokConfig.Contains(','))) {
        throw 'NgrokConfig ?????? ????????? ?? ???????????? ????; ??????? ? ???? ?? ??????????????.'
    }
    if ($NgrokApiPort -ne 0 -and $NgrokApiPort -eq $Port) {
        throw '???? API ngrok ?????? ?????????? ?? ????? ?????????? ??????????.'
    }
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion -lt [version]'5.1') {
        throw 'Нужны Windows 10/11 и Windows PowerShell 5.1 или PowerShell 7.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $origin = Get-TunnelOrigin $LocalHost $Port
    Write-Host "========================================`nHTTPS Tunnel Setup: $Provider`nЛокальный сервер: $origin`nWebhook path: $WebhookPath`n========================================"
    Write-TunnelMessage WARN 'Туннель публикует весь HTTP-сервер, включая UI. Используйте авторизацию приложения и только учебные данные.'
    Assert-TunnelServer $LocalHost $Port $origin $HealthPath
    $client = $null; $mutex = $null; $locked = $false; $temp = $null; $environment = @{}
    try {
        $mutex = New-Object Threading.Mutex($false, "Local\InfrastructureTunnels_${Provider}_${LocalHost}_$Port")
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Такой туннель уже запускается из этих скриптов. Остановите прежний через Ctrl+C.' }
        $processName = switch ($Provider) { cloudflare { 'cloudflared' }; ngrok { 'ngrok' }; localtunnel { 'node' } }
        if (@(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-TunnelMessage WARN "Обнаружены процессы $processName. Это могут быть другие туннели/приложения; они не будут остановлены. Проверьте, что новый запуск нужен."
        }
        $exeName = switch ($Provider) { cloudflare { 'cloudflared.exe' }; ngrok { 'ngrok.exe' }; localtunnel { 'node.exe' } }
        $exe = Get-TunnelCommand $exeName
        if (-not $exe) {
            $package = switch ($Provider) { cloudflare { 'Cloudflare.cloudflared' }; ngrok { 'Ngrok.Ngrok' }; localtunnel { 'OpenJS.NodeJS.LTS' } }
            $download = switch ($Provider) { cloudflare { 'https://developers.cloudflare.com/tunnel/downloads/' }; ngrok { 'https://ngrok.com/downloads/windows' }; localtunnel { 'https://nodejs.org/en/download' } }
            Install-TunnelTool $package $download -InstallIfMissing:$InstallIfMissing
            $exe = Get-TunnelCommand $exeName
            if (-not $exe) { throw "Установка завершилась, но $exeName не найден. Откройте новый терминал или добавьте официальный portable-каталог в PATH." }
        }
        Write-Host "Goal: Проверить версию клиента`nRUN: $exe --version"
        & $exe --version
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось проверить версию клиента.' }
        $arguments = @()
        switch ($Provider) {
            'cloudflare' {
                foreach ($name in @('config.yml', 'config.yaml')) {
                    if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE ".cloudflared\$name")) {
                        throw 'Найдена существующая конфигурация .cloudflared. Quick Tunnel может конфликтовать с ней. Используйте отдельный профиль Windows или самостоятельно сохраните и временно переместите конфигурацию; скрипт её не изменяет.'
                    }
                }
                Write-TunnelMessage WARN 'Quick Tunnel: временный URL, нет SLA/SSE, до 200 одновременных запросов.'
                $arguments = @('tunnel', '--url', $origin, '--no-autoupdate')
            }
            'ngrok' {
                if ($NgrokApiPort -eq 0) {
                    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
                    $listener.Start()
                    try { $NgrokApiPort = $listener.LocalEndpoint.Port } finally { $listener.Stop() }
                }
                if (Test-TunnelTcp '127.0.0.1' $NgrokApiPort) { throw 'Служебный порт занят. Укажите другой -NgrokApiPort.' }
                if (-not $NgrokConfig) {
                    foreach ($candidate in @("$env:LOCALAPPDATA\ngrok\ngrok.yml", "$env:USERPROFILE\.ngrok2\ngrok.yml")) {
                        if (Test-Path -LiteralPath $candidate) { $NgrokConfig = $candidate; break }
                    }
                }
                $version = '3'; $hasToken = -not [string]::IsNullOrWhiteSpace($env:NGROK_AUTHTOKEN)
                if ($NgrokConfig) {
                    $NgrokConfig = (Resolve-Path -LiteralPath $NgrokConfig).Path
                    if ($NgrokConfig.Contains(',')) { throw 'Путь конфигурации ngrok не должен содержать запятую.' }
                    $configText = [IO.File]::ReadAllText($NgrokConfig)
                    if ($configText -match '(?m)^version:\s*["'']?([23])') { $version = $Matches[1] }
                    else { throw 'Поддерживается конфигурация ngrok v2/v3. Проверьте её через ngrok config check.' }
                    $hasToken = $hasToken -or ($configText -match '(?m)^\s*authtoken:\s*[^\s#]+')
                    $configText = $null
                    Write-Host 'Goal: Проверить конфигурацию ngrok без вывода её содержимого'
                    Write-Host 'RUN: ngrok config check --config <выбранный файл>'
                    $null = & $exe config check --config $NgrokConfig 2>&1
                    if ($LASTEXITCODE -ne 0) { throw 'Конфигурация ngrok некорректна. Проверьте ngrok config check и версию клиента. Файл не изменён.' }
                }
                if (-not $hasToken) {
                    Write-TunnelMessage INFO 'Зарегистрируйтесь: https://dashboard.ngrok.com/get-started/your-authtoken . Нужен authtoken, не API key. Можно настроить постоянный профиль командой ngrok config add-authtoken <TOKEN>; она сохраняет секрет вне проекта, но может оставить его в истории.'
                    $secure = Read-Host 'Введите authtoken скрыто для текущего запуска (Enter — отмена)' -AsSecureString
                    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
                    try { $environment['NGROK_AUTHTOKEN'] = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
                    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
                    if ([string]::IsNullOrWhiteSpace($environment['NGROK_AUTHTOKEN'])) { throw 'Авторизация отменена. Настройте authtoken и повторите запуск.' }
                }
                $temp = Join-Path ([IO.Path]::GetTempPath()) ('tunnels_' + [guid]::NewGuid().ToString('N') + '.yml')
                $apiSetting = "web_addr: 127.0.0.1:$NgrokApiPort"
                $content = if ($version -eq '3') { "version: 3`nagent:`n  $apiSetting`n" } else { "version: 2`n$apiSetting`n" }
                [IO.File]::WriteAllText($temp, $content)
                $configs = if ($NgrokConfig) { $NgrokConfig + ',' + $temp } else { $temp }
                $arguments = @('http', $origin, '--config', $configs, '--log', 'stdout', '--log-format', 'json')
                Write-TunnelMessage INFO "Служебный API/инспектор: http://127.0.0.1:$NgrokApiPort . Порт выделен этому запуску."
            }
            'localtunnel' {
                $npm = Get-TunnelCommand 'npm.cmd'; $npx = Get-TunnelCommand 'npx.cmd'
                if (-not $npm -or -not $npx) { throw 'Нужны npm и npx из официального Node.js LTS. Переустановите Node.js или исправьте PATH.' }
                foreach ($tool in @($npm, $npx)) {
                    Write-Host "Goal: Проверить npm/npx`nRUN: $tool --version"
                    & $tool --version
                    if ($LASTEXITCODE -ne 0) { throw 'npm/npx не работает. Установите актуальный Node.js LTS.' }
                }
                if ((Get-TunnelHttpStatus 'https://registry.npmjs.org/localtunnel') -eq 0) { throw 'npm registry не отвечает. Проверьте DNS/TLS/proxy; это не доказывает отсутствие интернета вообще.' }
                Write-TunnelMessage WARN 'npx может скачать localtunnel из npm. Страница reminder/password может мешать webhook; защита не обходится.'
                if (-not $InstallIfMissing -and (Read-Host 'Разрешить npx загрузить и запустить localtunnel? [Y/N]') -notmatch '^(?i:y|yes)$') { throw 'Запуск npx отменён.' }
                # Run the npx JS entry point with node directly: no cmd.exe quoting or shell injection.
                $npxCli = Join-Path (Split-Path $npx) 'node_modules\npm\bin\npx-cli.js'
                if (-not (Test-Path -LiteralPath $npxCli)) { throw 'Не найден npx-cli.js рядом с npx.cmd. Используйте официальный Node.js LTS.' }
                $arguments = @($npxCli, '--yes', '--registry=https://registry.npmjs.org', '--package=localtunnel', '--', 'lt', '--port', [string]$Port, '--local-host', $LocalHost)
            }
        }
        $client = New-TunnelClient $exe $arguments $environment
        $environment.Clear()
        $url = Wait-TunnelUrl $client $Provider $StartupTimeoutSeconds $NgrokApiPort $origin -VerboseOutput:$VerboseOutput
        if ($client.Process.HasExited) { throw 'Клиент завершился после получения URL.' }
        Write-TunnelMessage OK "HTTPS URL получен. PID клиента: $($client.Process.Id)."
        if (-not $SkipPublicCheck) {
            $status = Get-TunnelHttpStatus ($url + $HealthPath)
            if ($status -gt 0) { Write-TunnelMessage CHECK "Публичный HTTPS endpoint отвечает: HTTP $status. Ответ может принадлежать провайдеру; доставка в приложение не подтверждена." }
            else { Write-TunnelMessage WARN 'Публичный HTTPS не ответил: возможна задержка DNS/TLS, proxy/VPN или блокировка. Туннель оставлен работать; повторите GET вручную.' }
        } else { Write-TunnelMessage WARN 'Публичная HTTPS-проверка пропущена.' }
        Write-Host "========================================`nURL RECEIVED`nProvider: $Provider`nLocal server: $origin`nPublic URL: $url`nWEBHOOK URL: $(Join-TunnelWebhook $url $WebhookPath)`n========================================"
        Write-TunnelMessage INFO 'Скопируйте WEBHOOK URL в ваш Web UI. Можно использовать другой внешний клиент. Для браузерных запросов проверьте CORS/OPTIONS в приложении.'
        Write-TunnelMessage WARN 'Webhook POST не выполнялся; работоспособность workflow не подтверждена. localtunnel/ngrok могут показывать страницу подтверждения.'
        Write-TunnelMessage INFO 'Туннель работает, пока запущен скрипт. Для остановки нажмите Ctrl+C.'
        while (-not $client.Process.HasExited) {
            # Drain continuously to prevent unbounded output accumulation.
            $line = $client.ReadLine()
            while ($null -ne $line) {
                if ($VerboseOutput) {
                    $code = [regex]::Match($line, 'ERR_NGROK_\d+')
                    if ($code.Success) { Write-TunnelMessage WARN $code.Value }
                }
                $line = $client.ReadLine()
            }
            Start-Sleep -Milliseconds 250
        }
        throw "Клиент туннеля завершился (код $($client.Process.ExitCode)). URL больше не считается доступным; проверьте сеть и повторите запуск."
    } finally {
        $environment.Clear()
        if ($null -ne $client) { $client.Dispose() }
        if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force }
        if ($locked) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}
