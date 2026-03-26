# Wellvo — Daily Check-In App for Families

One person sends check-in requests. Their loved ones tap "I'm OK." If no response, escalation alerts fire. Simple, private, and built for ages 13 to 95.

## Architecture

```
iOS App ──── SwiftUI + MVVM ──── Supabase Auth + Realtime
                                       │
Edge Functions ── Deno HTTP server ─────┘
   7 endpoints: check-in, escalation, subscriptions, invites
                                       │
Database ──── PostgreSQL + pg_cron ─────┘
                                       │
Website ──── React + Vite ──── Cloudflare Pages
```

**Hosting:** Contabo VPS via Coolify (Docker). Database and edge functions share a Docker network.

## Getting Started

### Website

```bash
cd website
npm install
npm run dev       # http://localhost:5173
npm run build     # Production build to dist/
```

### Edge Functions (requires [Deno](https://deno.land))

```bash
cp edge-functions/.env.example edge-functions/.env
# Fill in env vars
cd edge-functions
deno run --allow-net --allow-env server.ts
```

Or via Docker:

```bash
docker compose up --build    # Runs on port 9000
```

### iOS App (requires Xcode 15+ on macOS)

1. Copy `ios/Wellvo/BuildConfig.xcconfig.example` to `BuildConfig.xcconfig`
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`
3. Open `ios/Wellvo.xcodeproj` in Xcode and build

### Database Migrations

Migrations are in `supabase/migrations/` and run in order:

```bash
psql "$DATABASE_URL" -f supabase/migrations/00001_create_core_tables.sql
# ... through 00006
```

CI runs migrations automatically on push to `main` (requires GitHub environment approval).

## Project Structure

| Directory | Description |
|-----------|-------------|
| `ios/` | Swift iOS app (SwiftUI, MVVM, iOS 16+, StoreKit 2) |
| `edge-functions/` | Deno HTTP server with 7 function handlers |
| `website/` | React + TypeScript + Vite, deployed to Cloudflare Pages |
| `supabase/migrations/` | PostgreSQL migrations (core tables, RLS, pg_cron) |
| `.github/workflows/` | CI/CD: iOS build, edge functions deploy, migrations |
| `coolify/` | Deployment guide and backup script |

## Documentation

- **[Wellvo-PRD-v1.md](./Wellvo-PRD-v1.md)** — Full product requirements document
- **[coolify/README-DEPLOYMENT.md](./coolify/README-DEPLOYMENT.md)** — Production deployment guide
- **[CLAUDE.md](./CLAUDE.md)** — AI development context

## Task Tracking

- `prd.json` — User stories with completion status (Ralph loop format)
- `progress.txt` — Append-only implementation log

## License

All rights reserved. Copyright 2026 Pearson Media LLC.
