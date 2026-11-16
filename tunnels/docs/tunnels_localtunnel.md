# localtunnel

localtunnel запускается через npx без глобальной установки пакета. Нужны официальный [Node.js LTS](https://nodejs.org/en/download), npm и npx. Скрипт может предложить winget; при недоступности установки для пользователя используйте официальный Windows zip нужной архитектуры, распакуйте и добавьте каталог в PATH.

```powershell
node --version
npm.cmd --version
npx.cmd --version
.\tunnels\tunnels_start_localtunnel.ps1 -Port 5678 -WebhookPath /webhook/my-agent
```

Сначала проверяется доступность npm registry. Перед запуском пользователь разрешает npx скачать и выполнить пакет; `-InstallIfMissing` заранее разрешает это действие. Используется официальный npm registry и эквивалент `npx --yes --package=localtunnel -- lt --port 5678 --local-host 127.0.0.1`. В Windows скрипт вызывает `npx-cli.js` через `node.exe`, чтобы не интерпретировать параметры через cmd.exe. Старый npm без `--yes` нужно обновить вместе с Node.js LTS. Нестандартная раскладка npx без соседнего `node_modules/npm/bin/npx-cli.js` не поддерживается.

Скопируйте `WEBHOOK URL` из блока `URL RECEIVED`. URL временный. Ctrl+C останавливает клиент и его потомков. После перезапуска обновите URL в UI.

На публичном адресе может появиться reminder/password page. HTTP 200 от такой страницы не означает работу webhook. Скрипт не вводит пароль и не добавляет заголовки обхода. Если ручной браузерный доступ работает, а автоматические запросы получают HTML, выберите Cloudflare или ngrok. Этот вариант менее предсказуем для автоматических API-запросов.

Источник: [localtunnel README](https://github.com/localtunnel/localtunnel).
