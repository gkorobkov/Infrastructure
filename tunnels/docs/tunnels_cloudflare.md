# Cloudflare Quick Tunnel

Quick Tunnel создаёт временный `*.trycloudflare.com` без аккаунта и собственного домена. Установите cloudflared через предложение скрипта или [официальную загрузку](https://developers.cloudflare.com/tunnel/downloads/), выбрав архитектуру Windows. Portable-файл можно поместить в пользовательский каталог PATH.

```powershell
# Из корня репозитория; n8n уже запущен
.\tunnels\tunnels_start_cloudflare.ps1 -Port 5678 -WebhookPath /webhook/my-agent
# FastAPI уже запущен, например uvicorn на 8000
.\tunnels\tunnels_start_cloudflare.ps1 -Port 8000 -WebhookPath /api/hook -HealthPath /health
```

Клиент выполняет `cloudflared tunnel --url http://127.0.0.1:<порт>`. В блоке `URL RECEIVED` скопируйте полный `WEBHOOK URL`. Проверьте GET к безопасному health endpoint и его появление в локальном журнале; POST проверяйте отдельно из UI. Для n8n активируйте тестовое ожидание либо опубликуйте workflow. Ctrl+C закрывает клиент. При новом запуске адрес меняется — обновите его в UI.

При наличии `%USERPROFILE%\.cloudflared\config.yml` или `config.yaml` скрипт остановится: существующий профиль может конфликтовать с Quick Tunnel. Он не удаляется и не переименовывается автоматически. Используйте отдельный профиль Windows либо самостоятельно сохраните и временно переместите конфигурацию, затем восстановите её после работы.

Нет SLA, SSE не поддерживается, одновременно допускается до 200 запросов; превышение даёт HTTP 429. Для стабильного production-адреса нужен управляемый туннель, который эти скрипты не создают. При сетевых сбоях проверьте DNS/TLS, VPN/proxy, ограничения сети и [диагностику](tunnels_troubleshooting.md), затем попробуйте ngrok.

Источник: [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).
