# Wellvo — Project Configuration

## Overview
Wellvo (marketed as "Alive") is a daily check-in app for families. Owners send check-in requests; Receivers tap "I'm OK." Escalation alerts fire if no response.

## Tech Stack
- **iOS App**: Swift 5.9+, SwiftUI, MVVM, iOS 16+, StoreKit 2
- **Edge Functions**: Deno (TypeScript), single HTTP server routing to 7 function handlers
- **Database**: PostgreSQL via self-hosted Supabase, RLS, pg_cron
- **Website**: React + TypeScript + Vite, deployed to Cloudflare Pages
- **CI/CD**: GitHub Actions (iOS build, edge function Docker deploy, Supabase migrations)
- **Hosting**: Contabo VPS via Coolify (Docker)

## Directory Structure
```
ios/                    # iOS app (Xcode project)
  Wellvo/
    App/                # AppDelegate, WellvoApp, AppState, ContentView
    Models/             # CheckIn, User, Family, ReceiverSettings, etc.
    Services/           # Auth, CheckIn, Subscription, Push, Offline, Analytics
    ViewModels/         # Auth, Dashboard, Onboarding, Receiver
    Views/              # SwiftUI views organized by feature
    Utilities/          # Configuration, Keychain, NetworkRetry
edge-functions/         # Deno edge functions server
  server.ts             # Main HTTP router (CORS, rate limiting, auth, logging)
  shared/               # auth.ts, supabase.ts, apns.ts, sms.ts, rate-limiter.ts, logger.ts
  functions/            # Individual function handlers (7 endpoints)
website/                # React + Vite website
  src/
    pages/              # Home, Pricing, Privacy, Terms, Support, NotFound
    components/         # Header, Footer, Layout, ErrorBoundary
supabase/migrations/    # SQL migrations (00001-00006)
.github/workflows/      # CI/CD pipelines
coolify/                # Deployment guide and backup script
```

## Build Commands
```bash
# Website
cd website && npm install && npm run build    # Build
cd website && npm run dev                     # Dev server

# Edge Functions (requires Deno)
cd edge-functions && deno run --allow-net --allow-env server.ts

# Docker (edge functions)
docker compose up --build

# iOS (requires Xcode on macOS)
xcodebuild -project ios/Wellvo.xcodeproj -scheme Wellvo build
```

## Key Architecture Decisions
- Edge functions run as a single Deno HTTP server (not Supabase-hosted Edge Functions)
- CORS restricted to https://wellvo.net (configurable via ALLOWED_ORIGIN env var)
- Rate limiting is in-memory (resets on container restart, single-instance deploy)
- iOS app reads Supabase URL/keys from BuildConfig.xcconfig → Info.plist
- pg_cron triggers edge functions via HTTP with service role key
- Migrations require GitHub environment approval + pre-migration backup

## Common Gotchas
- iOS: Supabase config comes from Info.plist, injected via BuildConfig.xcconfig
- Edge functions: Deno, not Node.js — use Deno APIs and import maps (deno.json)
- CORS: iOS native apps don't send Origin headers; CORS logic must allow missing Origin
- Rate limiter: In-memory, not shared across instances (fine for current single-container setup)
- Website: Cloudflare Pages reads _headers and _redirects from public/ directory
- Migrations: Each migration wraps in BEGIN/COMMIT; verify with table/RLS/trigger counts

## Task Tracking
- `prd.json` — User stories with `passes: true/false` status (Ralph loop format)
- `progress.txt` — Append-only log with story status and iteration details
- PRD: `Alive-PRD-v1.md` — Full product requirements document
