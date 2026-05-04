# Synetik.IO deployment path

## Local run

Windows fallback:

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Port 4173
```

Windows shortcut:

```text
start-synetik.bat
```

Local URL:

```text
http://127.0.0.1:4173
```

Node route:

```powershell
node server.js
```

Open:

```text
http://localhost:4173
```

Leads are stored at:

```text
data/leads.jsonl
```

Analytics events are stored at:

```text
data/analytics.jsonl
```

## Termux run

```bash
pkg update
pkg install nodejs
cd /sdcard/Download/synetik-site
PORT=4173 node server.js
```

Open on the same phone:

```text
http://127.0.0.1:4173
```

Open from another device on the same Wi-Fi:

```text
http://PHONE_LOCAL_IP:4173
```

## Recommended production path

Best first production route:

```text
Cloudflare Registrar/DNS + Render Web Service
```

Why:

1. Cloudflare gives domain registration, DNS, SSL, CDN, DNSSEC and domain lock in one place.
2. Render runs this Node server without rewriting the backend.
3. Render supports custom domains and managed TLS.
4. The current JSONL lead/analytics storage works for validation and can later move to Supabase/Postgres.

## Render deploy

1. Create a GitHub repository.
2. Push this folder to GitHub.
3. In Render, create a new Blueprint from the repository.
4. Render reads `render.yaml`.
5. Confirm:
   - service name: `synetik-io`
   - runtime: Node
   - start command: `npm start`
   - health check: `/health`

## Cloudflare domain

Recommended domain hierarchy:

```text
synetik.io        primary brand
www.synetik.io    public website
app.synetik.io    future Synetik.IO Platform
rest.synetik.io   future Syn3tik R3st product
api.synetik.io    future API gateway
```

DNS records after Render gives the target:

```text
www  CNAME  RENDER_TARGET
@    CNAME  RENDER_APEX_TARGET
```

If Render gives an A record for apex, use:

```text
@    A      RENDER_IP
www  CNAME  RENDER_TARGET
```

Cloudflare settings:

```text
SSL/TLS: Full
Always Use HTTPS: On
DNSSEC: On
Domain Lock: On
Proxy: On, unless Render custom-domain verification asks for DNS-only temporarily
```

## Production environment

Minimum production environment:

```text
PORT=4173
NODE_ENV=production
```

On Render, `PORT` is injected automatically. Do not hardcode it.
