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

## Ralph — Autonomous Build Loop

Ralph (from [Snarktank](https://snarktank.dev)) is an autonomous AI development loop that uses Claude Code CLI to implement user stories from `prd.json` one at a time, unattended.

### Files

| File | Purpose |
|------|---------|
| `ralph.ps1` | Main loop script — reads `prd.json`, picks next incomplete story, runs Claude Code |
| `ralph-prompt.md` | Instructions sent to Claude Code each iteration |
| `ralph-headless.ps1` | Windowless launcher — runs Ralph in a hidden background process |
| `prd.json` | User stories with `"passes": true/false` status |
| `progress.txt` | Append-only log updated after each completed story |
| `.ralph-logs/` | Per-story and session logs (gitignored) |

### Running Ralph

**Interactive** (shows progress in terminal):
```powershell
.\ralph.ps1
.\ralph.ps1 -MaxIterations 50 -MaxTurns 100
.\ralph.ps1 -StopOnFail
```

**Headless** (no window, runs in background):
```powershell
.\ralph-headless.ps1
.\ralph-headless.ps1 -MaxIterations 50 -MaxTurns 100
```

### Monitoring a Headless Run

```powershell
# Tail the session log
Get-Content .ralph-logs\ralph-session_*.log -Wait -Tail 20

# Check source control for changes
git log --oneline -10
```

### Stopping Ralph

```powershell
# Read the saved PID and stop it
Stop-Process -Id (Get-Content .ralph-logs\ralph.pid)
```

### How It Works

1. Reads `prd.json` and finds the first story where `"passes": false` (lowest priority number)
2. Sends `ralph-prompt.md` to Claude Code CLI in non-interactive mode (`-p` flag)
3. Claude implements the story, updates `prd.json` and `progress.txt`, and commits
4. Loop repeats until all stories pass or max iterations reached
5. Each iteration is logged to `.ralph-logs/` with the story ID and timestamp

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-MaxIterations` | 120 | Maximum loop iterations before stopping |
| `-MaxTurns` | 75 | Max Claude Code turns per story (limits context usage) |
| `-Delay` | 10 | Seconds to pause between iterations |
| `-StopOnFail` | off | Stop the loop if Claude exits with an error |

Commits are co-authored by `Ralph <ralph@snarktank.dev>`.

## License

All rights reserved. Copyright 2026 Pearson Media LLC.
