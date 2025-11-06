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

The script will:
- Ensure a `.env` exists (create from template if missing)
- Generate ENCRYPTION_KEY if it’s the placeholder
- Pull and start containers
- Print the n8n URL when ready

Then open n8n at your domain and activate the Telegram workflow.

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