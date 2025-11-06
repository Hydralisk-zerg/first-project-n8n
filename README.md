# n8n + OCR стек (Telegram intake)

Этот репозиторий содержит самохостинговый стек n8n со следующим функционалом:

- Триггер Telegram с разветвлением по типу сообщения (текст vs документ)
- Асинхронный OCR‑микросервис (Poppler + Tesseract; DOC/DOCX через Gotenberg)
- Cloudflare Tunnel перед n8n (доступ только через туннель)
- PostgreSQL для хранения данных n8n

Стек запускается через Docker Compose и не открывает n8n напрямую наружу — только через ваш Cloudflare туннель.

## Предпосылки

- Docker Desktop (Windows/macOS) или Docker Engine (Linux)
- Аккаунт Cloudflare и токен именованного туннеля
- Токен Telegram‑бота (BotFather)

## Быстрый старт (Windows PowerShell)

1) Клонируйте репозиторий и откройте терминал в его каталоге.
2) Создайте файл `.env` из шаблона (или используйте скрипт деплоя, он сделает это сам):

```powershell
Copy-Item .env.example .env -Force
```

3) Отредактируйте `.env` и как минимум задайте:

- N8N_WEBHOOK_URL / N8N_EDITOR_BASE_URL / WEBHOOK_URL → ваш домен Cloudflare
- ENCRYPTION_KEY → длинная случайная строка
- CLOUDFLARED_TOKEN → из Cloudflare
- TELEGRAM_TOKEN → из BotFather

4) Запустите стек:

```powershell
scripts\deploy.ps1
```

Или полностью автоматический bootstrap (+ установка Docker Desktop):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; scripts\bootstrap.ps1
```

## Быстрый старт (Linux/macOS)

1) Клонируйте репозиторий и откройте терминал в его каталоге.
2) Создайте `.env` из шаблона (скрипт сделает это сам при отсутствии).
3) Запустите автоматический bootstrap, который установит/запустит Docker и развернёт проект:

```bash
bash scripts/bootstrap.sh
```

На macOS потребуется Docker Desktop и пользовательское подтверждение при первом запуске. Скрипт покажет подсказки, если потребуется ручное действие.

Скрипт выполнит:
- Проверит наличие `.env` (создаст из шаблона при отсутствии)
- Сгенерирует ENCRYPTION_KEY, если оставлен плейсхолдер
- Выполнит pull и поднимет контейнеры
- Выведет URL для доступа к n8n

Далее откройте n8n по вашему домену и активируйте Telegram‑воркфлоу.

Опционально: установить вебхук Telegram из скрипта

```powershell
# URL берите из Production URL узла Telegram Trigger (после активации воркфлоу)
scripts\set-telegram-webhook.ps1 -Url "https://YOUR_DOMAIN/webhook/<path>/webhook"

# Проверить текущую настройку вебхука
scripts\set-telegram-webhook.ps1 -InfoOnly
```

## Сервисы

- postgres:16-alpine → база данных n8n
- n8n:latest → движок автоматизации
- gotenberg:8 → конвертация Word→PDF для OCR
- ocr-api (node:18-alpine) → OCR‑микросервис
- cloudflared → публикует n8n через именованный Cloudflare туннель

## Заметки по вебхукам и Telegram

- Узел Telegram Trigger (в продакшене) показывает Production URL вебхука после активации воркфлоу.
- Установите вебхук Telegram ровно на этот URL. Если видите 404 — переактивируйте воркфлоу и скопируйте обновленный Production URL.
- За Cloudflare мы доверяем прокси‑заголовкам через `N8N_TRUSTED_PROXIES`.

## Данные и безопасность

- Рабочие данные и секреты хранятся в `data/n8n` и `data/postgres` и исключены из Git через `.gitignore`.
- Не коммитьте `.env`. Используйте `.env.example` как шаблон.
- Если токен Telegram был скомпрометирован — ротируйте его и обновите креды в n8n.

## Дополнительное усиление

- Установите `N8N_RUNNERS_ENABLED=true` в `.env`, чтобы включить task runners.
- Добавьте в Cloudflare WAF исключение для `/webhook/*`, если встретите 403/1020.
- Включите `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true`, чтобы убрать предупреждения о правах.

## Диагностика

- Если вебхуки возвращают 404, убедитесь, что воркфлоу активен и путь вебхука совпадает с Production URL из Telegram Trigger.
- Логи:

```powershell
docker compose logs n8n --tail 200
```

- Проверка рендера Compose:

```powershell
docker compose config
```

## Лицензия

Этот репозиторий содержит конфигурацию и обвязку вокруг n8n и вспомогательных сервисов. Лицензирование самого n8n определяется апстрим‑проектом — см. их лицензию.

---

# n8n + OCR stack (Telegram intake)

This repository contains a self-hosted n8n stack with:

- Telegram Trigger workflow that branches on text vs. document
- Asynchronous OCR microservice (Poppler + Tesseract; DOC/DOCX via Gotenberg)
- Cloudflare Tunnel in front of n8n
- PostgreSQL for n8n persistence

It’s designed to run via Docker Compose and exposes n8n only via your Cloudflare tunnel.

## Prerequisites

- Docker Desktop (Windows/macOS) or Docker Engine (Linux)
- A Cloudflare account and a named Tunnel token
- A Telegram Bot token from BotFather

## Quick start (Windows PowerShell)

1) Clone this repo and open it in a terminal.
2) Create your `.env` from the template (or use the deploy script to do it for you):

```powershell
Copy-Item .env.example .env -Force
```

3) Edit `.env` and set at minimum:

- N8N_WEBHOOK_URL / N8N_EDITOR_BASE_URL / WEBHOOK_URL → your Cloudflare domain
- ENCRYPTION_KEY → long random string
- CLOUDFLARED_TOKEN → from Cloudflare
- TELEGRAM_TOKEN → from BotFather

4) Start the stack:

```powershell
scripts\deploy.ps1
```

Or a fully automated bootstrap (installs Docker Desktop too):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; scripts\bootstrap.ps1
```

The script will:
- Ensure a `.env` exists (create from template if missing)
- Generate ENCRYPTION_KEY if it’s the placeholder
- Pull and start containers
- Print the n8n URL when ready

Then open n8n at your domain and activate the Telegram workflow.

Optional: set the Telegram webhook via helper script

```powershell
# Copy the Production URL from the Telegram Trigger node (after activating the workflow)
scripts\set-telegram-webhook.ps1 -Url "https://YOUR_DOMAIN/webhook/<path>/webhook"

# Inspect current webhook info
scripts\set-telegram-webhook.ps1 -InfoOnly
```

## Linux / macOS bootstrap

Use the `scripts/bootstrap.sh` helper:

```bash
bash scripts/bootstrap.sh
```

The script attempts to install Docker where possible, start the engine, and deploy the project. On macOS, Docker Desktop requires user confirmation.

## Linux / macOS bootstrap

Для Linux/macOS можно использовать скрипт `scripts/bootstrap.sh`:

```bash
bash scripts/bootstrap.sh
```

Скрипт попытается установить Docker (где возможно), запустить сервис и развернуть проект. На macOS потребуется Docker Desktop и подтверждение пользователем.

## Services

- postgres:16-alpine → n8n database
- n8n:latest → automation engine
- gotenberg:8 → Word→PDF conversion for OCR
- ocr-api (node:18-alpine) → OCR microservice
- cloudflared → publishes n8n via a Cloudflare named tunnel

## Notes on webhooks & Telegram

- The Telegram Trigger node provides a Production URL for webhooks once the workflow is activated.
- Set Telegram’s webhook to that exact URL. In case of 404s, re-activate the workflow and copy the fresh Production URL.
- Behind Cloudflare, we set proxy trust via `N8N_TRUSTED_PROXIES`.

## Data and security

- Runtime and secrets are stored in `data/n8n` and `data/postgres` and are excluded from Git via `.gitignore`.
- Do NOT commit `.env`. Use `.env.example` instead.
- Rotate your Telegram bot token if it was ever exposed and update credentials in n8n.

## Optional hardening

- Set `N8N_RUNNERS_ENABLED=true` in `.env` to use task runners.
- Add Cloudflare WAF bypass for `/webhook/*` if you see 403/1020.
- Set `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true` to silence permissions warnings.

## Troubleshooting

- If webhooks return 404, confirm the workflow is active and that the webhook path matches the Telegram Trigger’s Production URL.
- Check logs:

```powershell
docker compose logs n8n --tail 200
```

- Validate Compose rendering:

```powershell
docker compose config
```

## License

This repository contains configuration and scaffolding around n8n and supporting services. n8n itself is licensed per its upstream; consult their license for use.