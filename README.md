# Synetik.IO | Private Operating System

Public website and first operational backend for Synetik.IO.

## Run

```bash
npm start
```

Local URL:

```text
http://127.0.0.1:4173
```

## Production

Recommended path:

```text
Cloudflare DNS/SSL + Render Web Service
```

Render reads `render.yaml` and starts the service with:

```bash
npm start
```

## Data

Initial validation storage:

```text
data/leads.jsonl
data/analytics.jsonl
```

For production scale, migrate this layer to Supabase/Postgres.
