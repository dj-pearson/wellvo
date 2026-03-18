# Wellvo — Coolify Deployment Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Coolify VPS                    │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │         Supabase (Coolify Service)       │   │
│  │  ┌─────────┐  ┌──────┐  ┌───────────┐  │   │
│  │  │ Postgres │  │ Auth │  │  Realtime  │  │   │
│  │  │ + pg_cron│  │      │  │           │   │   │
│  │  └─────────┘  └──────┘  └───────────┘   │   │
│  │  ┌─────────┐  ┌──────┐  ┌───────────┐  │   │
│  │  │  Kong   │  │ Rest │  │  Storage   │  │   │
│  │  │  (API)  │  │      │  │           │   │   │
│  │  └─────────┘  └──────┘  └───────────┘   │   │
│  └──────────────────┬───────────────────────┘   │
│                     │ Docker Network             │
│  ┌──────────────────┴───────────────────────┐   │
│  │     Edge Functions (Docker Compose)      │   │
│  │  ┌─────────────────────────────────┐     │   │
│  │  │  Deno Server (port 9000)        │     │   │
│  │  │  - send-checkin-notification    │     │   │
│  │  │  - process-checkin-response     │     │   │
│  │  │  - escalation-tick              │     │   │
│  │  │  - on-demand-checkin            │     │   │
│  │  │  - subscription-webhook         │     │   │
│  │  │  - invite-receiver              │     │   │
│  │  └─────────────────────────────────┘     │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │             Cloudflare DNS               │   │
│  │  api.wellvo.net → Supabase Kong          │   │
│  │  edge.wellvo.net → Edge Functions        │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Step-by-Step Setup

### 1. Deploy Supabase on Coolify

1. In Coolify, go to **Services → New Service → Supabase**
2. Configure environment variables:
   - `POSTGRES_PASSWORD` — strong random password
   - `JWT_SECRET` — 32+ character secret
   - `SITE_URL` — `https://wellvo.net`
   - `API_EXTERNAL_URL` — `https://api.wellvo.net`
   - Enable Apple Sign-In provider
3. Deploy and note the **Docker network name** (usually `supabase_default`)
4. Run the SQL migrations in order:
   ```bash
   psql $DATABASE_URL -f supabase/migrations/00001_create_core_tables.sql
   psql $DATABASE_URL -f supabase/migrations/00002_rls_policies.sql
   psql $DATABASE_URL -f supabase/migrations/00003_pg_cron_jobs.sql
   ```

### 2. Configure Database Settings

Connect to the Postgres instance and set the app-level config:

```sql
ALTER DATABASE wellvo SET app.edge_functions_url = 'http://wellvo-edge-functions:9000';
ALTER DATABASE wellvo SET app.service_role_key = 'your-service-role-key';
```

### 3. Deploy Edge Functions

1. In Coolify, go to **Projects → New Resource → Docker Compose**
2. Point to this repository's `docker-compose.yml`
3. Set environment variables in Coolify:
   - `SUPABASE_URL` — internal Supabase URL (e.g., `http://supabase-kong:8000`)
   - `SUPABASE_SERVICE_ROLE_KEY` — from Supabase setup
   - `APNS_KEY_ID` — from Apple Developer portal
   - `APNS_TEAM_ID` — your Apple Team ID
   - `APNS_PRIVATE_KEY` — base64-encoded .p8 key
   - `APNS_ENVIRONMENT` — `development` or `production`
   - `SUPABASE_NETWORK` — Docker network name from step 1
4. Deploy

### 4. Configure Cloudflare DNS

| Record | Type  | Value                |
|--------|-------|----------------------|
| @      | A     | Your VPS IP          |
| api    | A     | Your VPS IP          |
| edge   | A     | Your VPS IP          |
| www    | CNAME | wellvo.net           |

Enable Cloudflare proxy (orange cloud) for all records.

### 5. Configure iOS App Secrets

In your GitHub repository **Settings → Secrets and Variables → Actions**, add:

| Secret                        | Description                              |
|-------------------------------|------------------------------------------|
| `APPLE_TEAM_ID`              | Your Apple Developer Team ID             |
| `BUILD_CERTIFICATE_BASE64`   | Base64-encoded .p12 distribution cert    |
| `P12_PASSWORD`               | Password for the .p12 file               |
| `PROVISIONING_PROFILE_BASE64`| Base64-encoded provisioning profile      |
| `PROVISIONING_PROFILE_NAME`  | Name of the provisioning profile         |
| `KEYCHAIN_PASSWORD`          | Temporary keychain password (any string) |
| `ASC_KEY_ID`                 | App Store Connect API Key ID             |
| `ASC_ISSUER_ID`              | App Store Connect API Issuer ID          |
| `ASC_PRIVATE_KEY`            | App Store Connect API .p8 key contents   |
| `SUPABASE_URL`               | `https://api.wellvo.net`                 |
| `SUPABASE_ANON_KEY`          | Supabase anonymous key                   |
| `SUPABASE_DB_URL`            | PostgreSQL connection string             |
| `COOLIFY_WEBHOOK_URL`        | Coolify deployment webhook URL           |
| `COOLIFY_API_TOKEN`          | Coolify API token                        |
| `EDGE_FUNCTIONS_HEALTH_URL`  | `https://edge.wellvo.net`                |

### 6. Database Backup Setup

The `backup-db.sh` script automates daily PostgreSQL backups with 30-day retention.

**Setup:**

```bash
# Copy script to server
scp coolify/backup-db.sh your-vps:/opt/wellvo/coolify/

# Make executable
chmod +x /opt/wellvo/coolify/backup-db.sh

# Add cron job (runs daily at 3 AM)
echo "0 3 * * * DATABASE_URL='postgresql://...' /opt/wellvo/coolify/backup-db.sh >> /var/log/wellvo-backup.log 2>&1" | crontab -

# Verify cron is set
crontab -l
```

**Configuration (environment variables):**

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | (required) | PostgreSQL connection string |
| `BACKUP_DIR` | `/var/backups/wellvo` | Where backups are stored |
| `RETENTION_DAYS` | `30` | Delete backups older than this |

**Restore from backup:**

```bash
# Decompress and restore
gunzip -c /var/backups/wellvo/wellvo-backup-20260318-030000.sql.gz | psql "$DATABASE_URL"
```

### 7. Apple Developer Setup

1. **App ID**: Register `net.wellvo.app` with capabilities:
   - Push Notifications
   - Sign in with Apple
   - Critical Alerts (requires justification)
2. **APNs Key**: Create in Certificates, Identifiers & Profiles → Keys
3. **Provisioning Profile**: App Store distribution profile
4. **App Store Connect**: Create the app, configure subscriptions:
   - `net.wellvo.family.monthly` — $4.99/mo
   - `net.wellvo.family.yearly` — $39.99/yr
   - `net.wellvo.familyplus.monthly` — $7.99/mo
   - `net.wellvo.familyplus.yearly` — $59.99/yr
   - `net.wellvo.addon.receiver` — $1.99/mo
   - `net.wellvo.addon.viewer` — $0.99/mo
