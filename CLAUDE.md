# Wellvo — Project Configuration

## Overview
Wellvo is a daily check-in app for families. Owners send check-in requests; Receivers tap "I'm OK." Escalation alerts fire if no response.

## Tech Stack
- **iOS App**: Swift 5.9+, SwiftUI, MVVM, iOS 16+, StoreKit 2
- **Android App**: Kotlin 1.9+, Jetpack Compose, MVVM, API 26+ (Android 8.0+), Google Play Billing
- **Edge Functions**: Deno (TypeScript), single HTTP server routing to 7 function handlers
- **Database**: PostgreSQL via self-hosted Supabase, RLS, pg_cron
- **Website**: React + TypeScript + Vite, deployed to Cloudflare Pages
- **CI/CD**: GitHub Actions (iOS build, Android build, edge function Docker deploy, Supabase migrations)
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
android/                # Android app (Gradle/Kotlin project)
  app/
    src/main/
      java/net/wellvo/android/
        di/             # Hilt dependency injection modules
        data/           # Models, Room entities, DAOs
        network/        # API service, error handling, retry
        services/       # Auth, CheckIn, Family, Location, Push, Offline, Subscription, Analytics
        viewmodels/     # Auth, Dashboard, Onboarding, Receiver, Settings, History, Family
        ui/             # Jetpack Compose screens organized by feature
        util/           # Configuration, SecureStorage, Extensions
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

# Android (requires JDK 17+)
cd android && ./gradlew assembleDebug         # Debug build
cd android && ./gradlew assembleRelease       # Release build
cd android && ./gradlew test                  # Unit tests
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
- Android: Supabase config comes from BuildConfig fields, set in build.gradle.kts from local.properties
- Android: EncryptedSharedPreferences replaces iOS Keychain for secure storage
- Android: FCM replaces APNs — edge functions must support both platforms (check push_tokens.platform)
- Android: WorkManager for background tasks (heartbeat, location) — minimum 15-min interval
- Android: POST_NOTIFICATIONS runtime permission required on Android 13+ (API 33)
- Edge functions: Deno, not Node.js — use Deno APIs and import maps (deno.json)
- CORS: Native apps (iOS + Android) don't send Origin headers; CORS logic must allow missing Origin
- Rate limiter: In-memory, not shared across instances (fine for current single-container setup)
- Website: Cloudflare Pages reads _headers and _redirects from public/ directory
- Migrations: Each migration wraps in BEGIN/COMMIT; verify with table/RLS/trigger counts

## Task Tracking
- `prd.json` — User stories with `passes: true/false` status (Ralph loop format)
- `progress.txt` — Append-only log with story status and iteration details
- PRD: `Wellvo-PRD-v1.md` — Full product requirements document
