# Wellvo — App Store Connect & Self-Hosted Supabase Complete Setup Guide

**Version 1.0 | March 2026**
**Pearson Media LLC**

---

## Table of Contents

1. [Apple App Store Connect — Full Metadata](#1-apple-app-store-connect--full-metadata)
2. [Apple Developer Portal Setup](#2-apple-developer-portal-setup)
3. [In-App Purchases & Subscriptions](#3-in-app-purchases--subscriptions)
4. [Self-Hosted Supabase Setup](#4-self-hosted-supabase-setup)
5. [Edge Functions Deployment](#5-edge-functions-deployment)
6. [DNS & Networking](#6-dns--networking)
7. [iOS Build & CI/CD Secrets](#7-ios-build--cicd-secrets)
8. [End-to-End Checklist](#8-end-to-end-checklist)

---

## 1. Apple App Store Connect — Full Metadata

### 1.1 App Information

| Field                  | Value                                |
| ---------------------- | ------------------------------------ |
| **App Name**           | Wellvo — Daily Check-In              |
| **Subtitle**           | One tap. Peace of mind.              |
| **Bundle ID**          | `net.wellvo.app`                     |
| **SKU**                | `wellvo-ios-001`                     |
| **Primary Language**   | English (U.S.)                       |
| **Primary Category**   | Lifestyle                            |
| **Secondary Category** | Health & Fitness                     |
| **Content Rights**     | Does not contain third-party content |
| **Age Rating**         | 4+ (no objectionable content)        |

### 1.2 Pricing & Availability

| Field              | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| **Base Price**     | Free (with In-App Purchases)                                 |
| **Availability**   | United States (expand to additional territories post-launch) |
| **Pre-Orders**     | Disabled for v1.0                                            |
| **Price Schedule** | N/A — Free download, subscription-based monetization         |

### 1.3 Version Information (v1.0.0)

#### App Store Description

```
Know your loved ones are OK — every single day.

Wellvo is the simplest way to stay connected to the people you care about most. Set up a daily check-in for your aging parent, teenager, or anyone you worry about. They get one notification. They tap one button. You get peace of mind.

HOW IT WORKS

For You (the Owner):
• Add family members and set their daily check-in time
• See real-time status on your dashboard — who's checked in, who hasn't
• Get escalating alerts if someone misses their check-in
• Send an on-demand "checking on you" ping anytime

For Your Loved One (the Receiver):
• One giant "I'm OK" button — that's the entire app
• Respond from the notification without even opening the app
• Optional mood indicator (happy / neutral / tired)
• No settings, no menus, no confusion

WHY FAMILIES LOVE WELLVO

✓ Not surveillance — no location tracking, no cameras, no sensors
✓ Works for ages 13 to 95 — designed for everyone
✓ One person manages everything — receivers never see billing or settings
✓ Escalation alerts so nothing slips through the cracks
✓ Streak tracking and check-in history for long-term peace of mind

PERFECT FOR
• Adult children with aging parents living independently
• Parents of teenagers who want a lightweight, respectful check-in
• Long-distance families and relationships
• Caregivers who need a simple daily signal

SUBSCRIPTION OPTIONS

Free: 1 receiver, daily check-in, 7-day history
Family ($4.99/mo or $39.99/yr): 2 receivers, 2 viewers, full escalation, mood tracking, 90-day history
Family+ ($7.99/mo or $59.99/yr): 5 receivers, 5 viewers, critical alerts, reports, unlimited history

Additional receivers ($1.99/mo each) and viewers ($0.99/mo each) available on paid plans.

Payment is charged to your Apple ID account at confirmation of purchase. Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your Apple ID account settings.

Privacy Policy: https://wellvo.net/privacy
Terms of Use: https://wellvo.net/terms
```

#### Promotional Text (170 chars, can be updated without new build)

```
The #1 daily check-in app for families. Know your aging parent or teenager is OK with one tap. No tracking. No surveillance. Just peace of mind.
```

#### Keywords (100 characters max)

```
check in,family safety,aging parents,daily check,senior safety,teen check in,caregiver,peace of mind
```

#### What's New (v1.0.0)

```
Welcome to Wellvo! Set up your first daily check-in and give your family peace of mind.
```

#### Support URL

```
https://wellvo.net/support
```

#### Marketing URL

```
https://wellvo.net
```

#### Privacy Policy URL

```
https://wellvo.net/privacy
```

### 1.4 App Store Screenshots Required

Screenshots must be provided for these device sizes:

| Device                          | Resolution  | Required               |
| ------------------------------- | ----------- | ---------------------- |
| iPhone 6.9" (iPhone 16 Pro Max) | 1320 x 2868 | Yes (required)         |
| iPhone 6.3" (iPhone 16 Pro)     | 1206 x 2622 | Yes (required)         |
| iPhone 6.7" (iPhone 15 Plus)    | 1290 x 2796 | Optional               |
| iPhone 6.5" (iPhone 11 Pro Max) | 1284 x 2778 | Optional               |
| iPhone 5.5" (iPhone 8 Plus)     | 1242 x 2208 | Yes (if supporting)    |
| iPad Pro 13"                    | 2048 x 2732 | Only if iPad supported |

**Recommended Screenshot Set (5–10 per device):**

1. **Hero** — Receiver "I'm OK" button with tagline "One tap. Peace of mind."
2. **Dashboard** — Owner dashboard showing 2-3 receivers with status cards
3. **Notification** — Lock screen showing actionable check-in notification
4. **Escalation** — Alert notification showing missed check-in escalation
5. **History** — Calendar heatmap with streaks and mood data
6. **Family** — Family member management screen with invite flow
7. **On-Demand** — Owner tapping "Check on Mom" quick action
8. **Setup** — Simple onboarding flow: "Who do you want to check on?"
9. **Mood** — Post-check-in mood selector (happy/neutral/tired)
10. **Settings** — Per-receiver schedule and escalation configuration

### 1.5 App Preview Video (Optional but Recommended)

| Spec       | Detail                              |
| ---------- | ----------------------------------- |
| Duration   | 15–30 seconds                       |
| Resolution | Match screenshot device sizes       |
| Format     | H.264, .mp4 or .mov                 |
| Audio      | Optional, muted by default on store |

**Storyboard suggestion:** Open with "Are they OK?" → show notification arrive → receiver taps "I'm OK" → owner sees green checkmark → close with "Wellvo. One tap. Peace of mind."

### 1.6 App Review Information

| Field                       | Value                               |
| --------------------------- | ----------------------------------- |
| **Contact First Name**      | (Your first name)                   |
| **Contact Last Name**       | (Your last name)                    |
| **Contact Email**           | support@wellvo.net                  |
| **Contact Phone**           | (Your phone number)                 |
| **Demo Account — Username** | demo@wellvo.net                     |
| **Demo Account — Password** | (Create a demo account in Supabase) |
| **Notes for Reviewer**      | See below                           |

**Review Notes:**

```
Wellvo is a family check-in app. To fully test:

1. OWNER ACCOUNT: Log in with the demo credentials above. This account has
   two test Receivers already configured.

2. PUSH NOTIFICATIONS: The app requires push notifications to function.
   The demo account has simulated check-in data visible on the dashboard.

3. CRITICAL ALERTS: This app uses Critical Alerts (com.apple.developer.usernotifications.critical-alerts)
   to notify Owners when a family member misses their check-in. This is a
   safety-critical feature for monitoring aging parents who may be in distress.
   The entitlement is only used for escalation step 3+ (missed check-in alerts
   to the Owner), never for marketing or non-urgent notifications.

4. SUBSCRIPTIONS: The app offers Free, Family ($4.99/mo), and Family+ ($7.99/mo)
   tiers. The demo account is on the Family tier.

5. SIGN IN WITH APPLE: Supported as primary auth method.

6. BACKGROUND APP REFRESH: Used for syncing offline check-ins when the device
   regains connectivity. No background location or audio.
```

### 1.7 App Privacy Details (Privacy Nutrition Labels)

You must declare data collection in App Store Connect under **App Privacy**.

#### Data Types Collected

| Data Type           | Category                      | Collected                   | Linked to Identity | Used for Tracking |
| ------------------- | ----------------------------- | --------------------------- | ------------------ | ----------------- |
| Email Address       | Contact Info                  | Yes                         | Yes                | No                |
| Name                | Contact Info                  | Yes                         | Yes                | No                |
| Phone Number        | Contact Info                  | Yes (optional, for invites) | Yes                | No                |
| User ID             | Identifiers                   | Yes                         | Yes                | No                |
| Product Interaction | Usage Data                    | Yes                         | Yes                | No                |
| Device ID           | Identifiers                   | No                          | —                  | No                |
| Location            | —                             | No                          | —                  | No                |
| Health & Fitness    | —                             | No                          | —                  | No                |
| Financial Info      | —                             | No                          | —                  | No                |
| Browsing History    | —                             | No                          | —                  | No                |
| Search History      | —                             | No                          | —                  | No                |
| Contacts            | —                             | No                          | —                  | No                |
| Photos or Videos    | Yes (profile photo, optional) | Yes                         | No                 |

#### Data Use Purposes

| Purpose           | Data Types Used                                                          |
| ----------------- | ------------------------------------------------------------------------ |
| App Functionality | Email, Name, Phone, User ID, Product Interaction                         |
| Analytics         | Product Interaction (via PostHog, privacy-first, no third-party sharing) |

#### Data Linked to You

- Email Address, Name, Phone Number (for account and invitations)
- User ID (for authentication)

#### Data NOT Collected

- Precise Location, Coarse Location
- Health, Fitness
- Financial Information
- Browsing/Search History
- Contacts list
- Sensitive Information

### 1.8 Export Compliance

| Question                         | Answer                                       |
| -------------------------------- | -------------------------------------------- |
| Uses encryption?                 | Yes (HTTPS/TLS for API communication)        |
| Contains proprietary encryption? | No                                           |
| Qualifies for exemption?         | Yes — uses standard HTTPS only               |
| Export Compliance Documentation  | Not required (standard encryption exemption) |

---

## 2. Apple Developer Portal Setup

### 2.1 App ID Registration

Go to **Certificates, Identifiers & Profiles → Identifiers → App IDs → Register**

| Field       | Value                       |
| ----------- | --------------------------- |
| Description | Wellvo iOS App              |
| Bundle ID   | `net.wellvo.app` (Explicit) |

**Enable these Capabilities:**

- [x] Push Notifications
- [x] Sign in with Apple
- [x] Critical Alerts _(requires separate entitlement request — see 2.4)_
- [x] Time Sensitive Notifications
- [x] Background Modes (Background App Refresh)

### 2.2 APNs Key (for Push Notifications)

Go to **Keys → Create a New Key**

| Field    | Value                                   |
| -------- | --------------------------------------- |
| Key Name | Wellvo APNs Key                         |
| Enable   | Apple Push Notifications service (APNs) |

After creation:

1. Download the `.p8` file — **you can only download it once**
2. Note the **Key ID** (10-character string)
3. Note your **Team ID** (from Membership page)
4. Base64-encode the .p8 for environment variables:
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
   ```

### 2.3 Provisioning Profiles

Create **two** provisioning profiles:

**Development:**
| Field | Value |
|-------|-------|
| Type | iOS App Development |
| App ID | net.wellvo.app |
| Certificates | Your dev certificate |
| Devices | Your test devices |

**Distribution:**
| Field | Value |
|-------|-------|
| Type | App Store Distribution |
| App ID | net.wellvo.app |
| Certificates | Your distribution certificate |

### 2.4 Critical Alerts Entitlement Request

Critical Alerts require a **separate approval from Apple**. Submit a request at:
**https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/**

**Justification template:**

```
App Name: Wellvo — Daily Check-In
Bundle ID: net.wellvo.app

Wellvo is a family safety app that monitors daily check-ins from aging parents
and vulnerable family members. When a family member fails to respond to their
daily check-in within the configured escalation window, the app sends a Critical
Alert to the monitoring family member (Owner).

This is a time-critical safety notification — a missed check-in from an elderly
parent living alone could indicate a fall, medical emergency, or other distress.
The Critical Alert ensures the Owner is notified even if their phone is in Do Not
Disturb or Sleep Focus mode.

Critical Alerts are ONLY used for:
- Missed check-in escalation (Step 3+) after configurable wait time
- Never for marketing, promotions, or non-urgent content

The target demographic includes 53+ million American caregivers for aging family
members, many of whom live remotely from their aging parents.
```

### 2.5 App Store Connect API Key

Go to **Users and Access → Integrations → App Store Connect API → Generate**

| Field  | Value                  |
| ------ | ---------------------- |
| Name   | Wellvo CI/CD           |
| Access | App Manager (or Admin) |

After creation:

1. Download the `.p8` private key — **one-time download**
2. Note the **Key ID**
3. Note the **Issuer ID** (shown at top of page)

### 2.6 Sign in with Apple — Service Configuration

Go to **Certificates, Identifiers & Profiles → Identifiers → Services IDs → Register**

| Field       | Value                                     |
| ----------- | ----------------------------------------- |
| Description | Wellvo Web Auth                           |
| Identifier  | `net.wellvo.auth`                         |
| Enable      | Sign in with Apple                        |
| Domains     | `api.wellvo.net`                          |
| Return URLs | `https://api.wellvo.net/auth/v1/callback` |

> Note: Also enable Apple Sign-In on your primary App ID (`net.wellvo.app`).

---

## 3. In-App Purchases & Subscriptions

### 3.1 Subscription Group

Create **one** subscription group in App Store Connect:

| Field          | Value          |
| -------------- | -------------- |
| Group Name     | Wellvo Premium |
| Reference Name | wellvo_premium |

### 3.2 Auto-Renewable Subscriptions

Create these products within the "Wellvo Premium" group:

#### Family Monthly

| Field              | Value                       |
| ------------------ | --------------------------- |
| Reference Name     | Family Monthly              |
| Product ID         | `net.wellvo.family.monthly` |
| Price              | $4.99 USD                   |
| Duration           | 1 Month                     |
| Subscription Group | Wellvo Premium              |
| Level of Service   | 2 (below Family+)           |

**Localization (English US):**
| Field | Value |
|-------|-------|
| Display Name | Family |
| Description | 2 receivers, 2 viewers, full escalation, mood tracking, 90-day history |

#### Family Yearly

| Field              | Value                      |
| ------------------ | -------------------------- |
| Reference Name     | Family Yearly              |
| Product ID         | `net.wellvo.family.yearly` |
| Price              | $39.99 USD (~33% savings)  |
| Duration           | 1 Year                     |
| Subscription Group | Wellvo Premium             |
| Level of Service   | 2                          |

**Localization (English US):**
| Field | Value |
|-------|-------|
| Display Name | Family (Annual) |
| Description | 2 receivers, 2 viewers, full escalation, mood tracking, 90-day history — save 33% |

#### Family+ Monthly

| Field              | Value                           |
| ------------------ | ------------------------------- |
| Reference Name     | Family Plus Monthly             |
| Product ID         | `net.wellvo.familyplus.monthly` |
| Price              | $7.99 USD                       |
| Duration           | 1 Month                         |
| Subscription Group | Wellvo Premium                  |
| Level of Service   | 1 (highest tier)                |

**Localization (English US):**
| Field | Value |
|-------|-------|
| Display Name | Family+ |
| Description | 5 receivers, 5 viewers, critical alerts, exportable reports, unlimited history, priority support |

#### Family+ Yearly

| Field              | Value                          |
| ------------------ | ------------------------------ |
| Reference Name     | Family Plus Yearly             |
| Product ID         | `net.wellvo.familyplus.yearly` |
| Price              | $59.99 USD (~37% savings)      |
| Duration           | 1 Year                         |
| Subscription Group | Wellvo Premium                 |
| Level of Service   | 1                              |

**Localization (English US):**
| Field | Value |
|-------|-------|
| Display Name | Family+ (Annual) |
| Description | 5 receivers, 5 viewers, critical alerts, exportable reports, unlimited history, priority support — save 37% |

### 3.3 Non-Renewing Subscriptions (Add-Ons)

> Note: Add-on receivers/viewers are implemented as **auto-renewable subscriptions** in a **separate** subscription group since they stack on top of the base plan.

Create a second subscription group:

| Field          | Value          |
| -------------- | -------------- |
| Group Name     | Wellvo Add-Ons |
| Reference Name | wellvo_addons  |

#### Add-On Receiver

| Field              | Value                       |
| ------------------ | --------------------------- |
| Reference Name     | Additional Receiver         |
| Product ID         | `net.wellvo.addon.receiver` |
| Price              | $1.99 USD                   |
| Duration           | 1 Month                     |
| Subscription Group | Wellvo Add-Ons              |

**Localization:**
| Field | Value |
|-------|-------|
| Display Name | Extra Receiver |
| Description | Add one additional receiver to your family plan |

#### Add-On Viewer

| Field              | Value                     |
| ------------------ | ------------------------- |
| Reference Name     | Additional Viewer         |
| Product ID         | `net.wellvo.addon.viewer` |
| Price              | $0.99 USD                 |
| Duration           | 1 Month                   |
| Subscription Group | Wellvo Add-Ons            |

**Localization:**
| Field | Value |
|-------|-------|
| Display Name | Extra Viewer |
| Description | Add one additional viewer to your family plan |

### 3.4 Introductory Offers (Recommended)

| Offer      | Applied To      | Type | Duration | Price |
| ---------- | --------------- | ---- | -------- | ----- |
| Free Trial | Family Monthly  | Free | 7 days   | $0    |
| Free Trial | Family+ Monthly | Free | 7 days   | $0    |
| Free Trial | Family Yearly   | Free | 14 days  | $0    |
| Free Trial | Family+ Yearly  | Free | 14 days  | $0    |

### 3.5 App Store Server Notifications V2

Configure in **App Store Connect → App → App Information → App Store Server Notifications**

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Production URL | `https://edge.wellvo.net/subscription-webhook` |
| Sandbox URL    | `https://edge.wellvo.net/subscription-webhook` |
| Version        | Version 2                                      |

**Notification types to handle:**

- `DID_CHANGE_RENEWAL_STATUS` — Subscription auto-renew toggled
- `DID_RENEW` — Subscription successfully renewed
- `EXPIRED` — Subscription expired
- `GRACE_PERIOD_EXPIRED` — Billing grace period ended
- `DID_FAIL_TO_RENEW` — Billing retry failed
- `SUBSCRIBED` — New subscription or resubscribe
- `DID_CHANGE_RENEWAL_INFO` — Upgrade/downgrade/crossgrade
- `REVOKE` — Refund or family sharing revocation
- `OFFER_REDEEMED` — Promotional or introductory offer redeemed

### 3.6 Subscription Review Notes

```
This app offers auto-renewable subscriptions:

Family ($4.99/month or $39.99/year):
- 2 receivers and 2 viewers in a family group
- Custom check-in schedules, on-demand check-ins
- Full escalation chain with configurable timing
- Mood tracking and pattern alerts
- 90-day check-in history

Family+ ($7.99/month or $59.99/year):
- 5 receivers and 5 viewers in a family group
- All Family features plus Critical Alerts (Do Not Disturb bypass)
- Exportable reports, unlimited history
- Priority support

Add-On Receiver ($1.99/month): Adds one additional receiver slot
Add-On Viewer ($0.99/month): Adds one additional viewer slot

Payment is charged to the user's Apple ID account at confirmation of purchase.
Subscriptions automatically renew unless cancelled at least 24 hours before
the end of the current period. The account will be charged for renewal within
24 hours prior to the end of the current period.

Users can manage subscriptions and turn off auto-renewal in Account Settings
after purchase.

Privacy Policy: https://wellvo.net/privacy
Terms of Use: https://wellvo.net/terms
```

---

## 4. Self-Hosted Supabase Setup

### 4.1 Infrastructure Prerequisites

| Component           | Requirement                        |
| ------------------- | ---------------------------------- |
| VPS Provider        | Contabo (or any VPS with 4GB+ RAM) |
| Deployment Platform | Coolify (self-hosted PaaS)         |
| OS                  | Ubuntu 22.04+ or Debian 12+        |
| Docker              | Docker Engine 24+                  |
| Domain              | wellvo.net (registered and active) |
| DNS Provider        | Cloudflare (free tier)             |

### 4.2 Deploy Supabase via Coolify

1. In Coolify dashboard: **Services → New Service → Supabase**
2. Configure these environment variables in Coolify:

```env
# ─── Core Supabase Config ───
POSTGRES_PASSWORD=<generate-strong-64-char-password>
JWT_SECRET=<generate-strong-32-char-secret>
ANON_KEY=<generate-via-supabase-jwt-tool>
SERVICE_ROLE_KEY=<generate-via-supabase-jwt-tool>

# ─── Generate JWT keys using: ───
# https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys
# Use your JWT_SECRET to generate ANON_KEY and SERVICE_ROLE_KEY

# ─── URLs ───
SITE_URL=https://wellvo.net
API_EXTERNAL_URL=https://api.wellvo.net
SUPABASE_PUBLIC_URL=https://api.wellvo.net

# ─── SMTP (for email auth, password reset) ───
SMTP_ADMIN_EMAIL=noreply@wellvo.net
SMTP_HOST=<your-smtp-host>
SMTP_PORT=587
SMTP_USER=<your-smtp-user>
SMTP_PASS=<your-smtp-password>
SMTP_SENDER_NAME=Wellvo

# ─── Auth Providers ───
GOTRUE_EXTERNAL_APPLE_ENABLED=true
GOTRUE_EXTERNAL_APPLE_CLIENT_ID=net.wellvo.auth
GOTRUE_EXTERNAL_APPLE_SECRET=<apple-sign-in-client-secret>
# Apple client secret must be a JWT signed with your Apple Services key
# See: https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens

# ─── PostgreSQL Extensions ───
# Ensure pg_cron is enabled (Supabase includes it by default)
```

3. Deploy and wait for all containers to become healthy
4. Note the **Docker network name** from Coolify (e.g., `supabase_default` or a Coolify-generated name)

### 4.3 Generate Supabase JWT Keys

Use the Supabase key generator or create manually:

```bash
# Install jwt-cli or use Node.js
# ANON_KEY: role = anon
# SERVICE_ROLE_KEY: role = service_role

# Using Node.js:
node -e "
const jwt = require('jsonwebtoken');
const secret = 'YOUR_JWT_SECRET_HERE';

const anon = jwt.sign({ role: 'anon', iss: 'supabase' }, secret, { expiresIn: '10y' });
const service = jwt.sign({ role: 'service_role', iss: 'supabase' }, secret, { expiresIn: '10y' });

console.log('ANON_KEY:', anon);
console.log('SERVICE_ROLE_KEY:', service);
"
```

### 4.4 Run Database Migrations

Connect to the Postgres instance and run migrations in order:

```bash
# Get the database URL from Coolify's Supabase service
# Format: postgresql://postgres:<POSTGRES_PASSWORD>@<host>:5432/postgres

# Run migrations in order
psql $DATABASE_URL -f supabase/migrations/00001_create_core_tables.sql
psql $DATABASE_URL -f supabase/migrations/00002_rls_policies.sql
psql $DATABASE_URL -f supabase/migrations/00003_pg_cron_jobs.sql
psql $DATABASE_URL -f supabase/migrations/00004_fix_invite_rls_and_addon_rpcs.sql
psql $DATABASE_URL -f supabase/migrations/00005_subscription_grace_period_and_retention.sql
psql $DATABASE_URL -f supabase/migrations/00006_sms_escalation_and_pattern_alerts.sql
```

### 4.5 Configure Database App Settings

```sql
-- Set Edge Functions URL (internal Docker network address)
ALTER DATABASE postgres SET app.edge_functions_url = 'http://wellvo-edge-functions:9000';

-- Set service role key for internal Edge Function calls from pg_cron
ALTER DATABASE postgres SET app.service_role_key = 'your-service-role-key-here';
```

### 4.6 Verify pg_cron is Active

```sql
-- Check extension is installed
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- Check scheduled jobs are registered
SELECT * FROM cron.job;

-- You should see jobs for:
-- - Check-in dispatching (per-receiver scheduled times)
-- - Escalation tick (every minute)
-- - Grace period enforcement (daily at 1 AM UTC)
-- - Data retention cleanup (daily at 3 AM UTC)
-- - Pattern drift detection (daily at 11 PM UTC)
```

### 4.7 Configure Supabase Auth — Apple Sign-In

In the Supabase dashboard (or via environment variables):

1. Go to **Authentication → Providers → Apple**
2. Enable Apple provider
3. Configure:
   | Field | Value |
   |-------|-------|
   | Client ID | `net.wellvo.auth` (your Services ID) |
   | Secret Key | JWT generated from Apple's private key |
   | Redirect URL | `https://api.wellvo.net/auth/v1/callback` |

**Generate Apple Client Secret (JWT):**

```javascript
// generate-apple-secret.js
const jwt = require("jsonwebtoken");
const fs = require("fs");

const privateKey = fs.readFileSync("AuthKey_XXXXXXXXXX.p8");
const token = jwt.sign({}, privateKey, {
  algorithm: "ES256",
  expiresIn: "180d",
  audience: "https://appleid.apple.com",
  issuer: "YOUR_TEAM_ID",
  subject: "net.wellvo.auth",
  keyid: "YOUR_KEY_ID",
});

console.log(token);
```

> Note: Apple client secrets expire after max 6 months. Set a reminder to regenerate.

### 4.8 Configure Supabase Storage (Profile Photos)

```sql
-- Create the storage bucket for avatars
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true);

-- RLS policy: users can upload their own avatar
CREATE POLICY "Users can upload own avatar" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- RLS policy: anyone can view avatars (they're public)
CREATE POLICY "Avatars are publicly accessible" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

-- RLS policy: users can update/delete their own avatar
CREATE POLICY "Users can update own avatar" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own avatar" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
```

---

## 5. Edge Functions Deployment

### 5.1 Docker Compose Environment Variables

Set these in Coolify for the Edge Functions Docker Compose service:

```env
# ─── Supabase Connection (internal Docker network) ───
SUPABASE_URL=http://supabase-kong:8000
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>

# ─── Apple Push Notification Service (APNs) ───
APNS_KEY_ID=<10-char-key-id-from-apple>
APNS_TEAM_ID=<10-char-team-id-from-apple>
APNS_PRIVATE_KEY=<base64-encoded-p8-key>
APNS_ENVIRONMENT=production
# Use "development" for sandbox testing, "production" for App Store builds
# development → api.sandbox.push.apple.com
# production → api.push.apple.com

# ─── Docker Networking ───
SUPABASE_NETWORK=<coolify-supabase-network-name>
# Find this with: docker network ls | grep supabase

# ─── Server Config ───
PORT=9000
```

### 5.2 APNs Environment Selection

| Build Type               | APNS_ENVIRONMENT | APNs Host                    |
| ------------------------ | ---------------- | ---------------------------- |
| Xcode Debug / TestFlight | `development`    | `api.sandbox.push.apple.com` |
| App Store Release        | `production`     | `api.push.apple.com`         |

> Important: TestFlight builds use the **sandbox** APNs environment. Only App Store distributed builds use production. If your Edge Functions are set to `production` but you're testing via TestFlight, push notifications will silently fail.

### 5.3 Deploy

```bash
# From the repository root
docker compose up -d

# Verify health
curl https://edge.wellvo.net/health
# Should return: {"status":"ok"}
```

### 5.4 Edge Function Endpoints Summary

| Endpoint                     | Method | Auth         | Trigger                           |
| ---------------------------- | ------ | ------------ | --------------------------------- |
| `/send-checkin-notification` | POST   | Service Role | pg_cron (scheduled)               |
| `/process-checkin-response`  | POST   | User JWT     | App / Notification Action         |
| `/escalation-tick`           | POST   | Service Role | pg_cron (every minute)            |
| `/on-demand-checkin`         | POST   | User JWT     | Owner taps "Check on [Name]"      |
| `/subscription-webhook`      | POST   | Apple Signed | App Store Server Notifications V2 |
| `/invite-receiver`           | POST   | User JWT     | Owner invites a receiver          |
| `/subscription-cancellation` | POST   | Service Role | Subscription lifecycle            |
| `/health`                    | GET    | None         | Monitoring                        |

---

## 6. DNS & Networking

### 6.1 Cloudflare DNS Records

| Record | Type  | Name   | Value        | Proxy            |
| ------ | ----- | ------ | ------------ | ---------------- |
| Root   | A     | `@`    | `<VPS-IP>`   | Proxied (orange) |
| API    | A     | `api`  | `<VPS-IP>`   | Proxied (orange) |
| Edge   | A     | `edge` | `<VPS-IP>`   | Proxied (orange) |
| WWW    | CNAME | `www`  | `wellvo.net` | Proxied (orange) |

### 6.2 Cloudflare SSL/TLS Settings

| Setting                  | Value         |
| ------------------------ | ------------- |
| SSL/TLS Mode             | Full (Strict) |
| Always Use HTTPS         | On            |
| Minimum TLS Version      | TLS 1.2       |
| Automatic HTTPS Rewrites | On            |

### 6.3 Coolify Reverse Proxy Configuration

Ensure Coolify's Traefik/Caddy is configured to route:

- `api.wellvo.net` → Supabase Kong container (port 8000)
- `edge.wellvo.net` → Edge Functions container (port 9000)
- `wellvo.net` → Landing page (if hosted on same VPS)

---

## 7. iOS Build & CI/CD Secrets

### 7.1 GitHub Repository Secrets

Set all of these in **GitHub → Repository → Settings → Secrets and Variables → Actions**:

| Secret                        | Description                   | Where to Get It                                           |
| ----------------------------- | ----------------------------- | --------------------------------------------------------- |
| `APPLE_TEAM_ID`               | 10-character Team ID          | Apple Developer → Membership                              |
| `BUILD_CERTIFICATE_BASE64`    | Base64 .p12 distribution cert | Keychain → Export cert → `base64 -i cert.p12`             |
| `P12_PASSWORD`                | Password for .p12 file        | Set when exporting from Keychain                          |
| `PROVISIONING_PROFILE_BASE64` | Base64 provisioning profile   | Download from Apple → `base64 -i profile.mobileprovision` |
| `PROVISIONING_PROFILE_NAME`   | Profile name string           | Shown in Apple Developer portal                           |
| `KEYCHAIN_PASSWORD`           | Any random string             | Generate: `openssl rand -hex 16`                          |
| `ASC_KEY_ID`                  | App Store Connect API Key ID  | App Store Connect → Keys                                  |
| `ASC_ISSUER_ID`               | App Store Connect Issuer ID   | App Store Connect → Keys (top of page)                    |
| `ASC_PRIVATE_KEY`             | .p8 key file contents         | Downloaded when creating ASC API key                      |
| `SUPABASE_URL`                | `https://api.wellvo.net`      | Your Supabase instance URL                                |
| `SUPABASE_ANON_KEY`           | Supabase anon JWT             | Generated in step 4.3                                     |
| `SUPABASE_DB_URL`             | PostgreSQL connection string  | `postgresql://postgres:<pw>@<host>:5432/postgres`         |
| `COOLIFY_WEBHOOK_URL`         | Coolify deploy webhook        | Coolify → Resource → Webhooks                             |
| `COOLIFY_API_TOKEN`           | Coolify API token             | Coolify → Settings → API Tokens                           |
| `EDGE_FUNCTIONS_HEALTH_URL`   | `https://edge.wellvo.net`     | Your edge functions URL                                   |

### 7.2 iOS Build Configuration

The file `ios/Wellvo/BuildConfig.xcconfig` should contain:

```xcconfig
SUPABASE_URL = https:$()/$()/api.wellvo.net
SUPABASE_ANON_KEY = your-anon-key-here
PRODUCT_BUNDLE_IDENTIFIER = net.wellvo.app
```

> Note: In CI/CD, these values are injected from GitHub Secrets, overriding the xcconfig defaults.

---

## 8. End-to-End Checklist

### Phase 1: Apple Developer Portal

- [ ] Register App ID `net.wellvo.app` with all capabilities
- [ ] Create APNs Key (.p8) and save Key ID
- [ ] Request Critical Alerts entitlement from Apple
- [ ] Create Services ID `net.wellvo.auth` for Sign in with Apple
- [ ] Create distribution certificate and provisioning profile
- [ ] Create App Store Connect API key (.p8)

### Phase 2: App Store Connect

- [ ] Create app with bundle ID `net.wellvo.app`
- [ ] Fill in all app metadata (name, subtitle, description, keywords)
- [ ] Set primary category (Lifestyle) and secondary (Health & Fitness)
- [ ] Create subscription group "Wellvo Premium" with 4 products
- [ ] Create subscription group "Wellvo Add-Ons" with 2 products
- [ ] Configure introductory offers (free trials)
- [ ] Set up App Store Server Notifications V2 URL
- [ ] Complete privacy nutrition labels
- [ ] Complete export compliance
- [ ] Prepare screenshots for required device sizes
- [ ] Write review notes with demo account credentials
- [ ] Set availability to United States

### Phase 3: Self-Hosted Supabase

- [ ] Deploy Supabase via Coolify with all environment variables
- [ ] Generate and set JWT keys (ANON_KEY, SERVICE_ROLE_KEY)
- [ ] Run all 6 SQL migrations in order
- [ ] Set database app config (edge_functions_url, service_role_key)
- [ ] Verify pg_cron extension and scheduled jobs
- [ ] Configure Apple Sign-In auth provider
- [ ] Create storage bucket for avatars
- [ ] Configure SMTP for email auth/password reset
- [ ] Create demo account for App Store review

### Phase 4: Edge Functions

- [ ] Set all environment variables in Coolify
- [ ] Deploy Docker Compose service
- [ ] Verify health endpoint responds
- [ ] Test APNs connectivity (sandbox first)
- [ ] Verify internal Supabase connectivity (Docker network)
- [ ] Verify subscription webhook endpoint accepts Apple notifications

### Phase 5: DNS & Networking

- [ ] Configure all Cloudflare DNS records (A and CNAME)
- [ ] Enable Cloudflare proxy on all records
- [ ] Set SSL/TLS to Full (Strict)
- [ ] Verify `api.wellvo.net` routes to Supabase Kong
- [ ] Verify `edge.wellvo.net` routes to Edge Functions
- [ ] Test HTTPS on all subdomains

### Phase 6: CI/CD

- [ ] Set all GitHub repository secrets (15 total)
- [ ] Verify iOS build workflow triggers on push to `ios/**`
- [ ] Verify edge functions deploy workflow triggers correctly
- [ ] Verify Supabase migrations workflow runs against correct DB
- [ ] Test full pipeline: push → build → upload to App Store Connect

### Phase 7: Pre-Submission Testing

- [ ] TestFlight build uploads successfully
- [ ] Push notifications work in sandbox (TestFlight)
- [ ] Apple Sign-In works end-to-end
- [ ] Subscription purchase flow works in sandbox
- [ ] Subscription webhook receives sandbox notifications
- [ ] Check-in flow works: schedule → notify → respond → dashboard update
- [ ] Escalation chain works through all steps
- [ ] On-demand check-in works
- [ ] Invite flow works via deep link
- [ ] Offline check-in queues and syncs when online
- [ ] Critical Alerts bypass DND (if entitlement approved)
- [ ] Demo account works for App Store review

### Phase 8: Submit for Review

- [ ] Upload final build via Xcode or CI/CD
- [ ] Select build in App Store Connect
- [ ] Verify all metadata, screenshots, and description
- [ ] Submit for review
- [ ] Monitor review status and respond to any questions

---

## Quick Reference: All Environment Variables

### Supabase (Coolify)

```
POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY,
SITE_URL, API_EXTERNAL_URL, SUPABASE_PUBLIC_URL,
SMTP_ADMIN_EMAIL, SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_SENDER_NAME,
GOTRUE_EXTERNAL_APPLE_ENABLED, GOTRUE_EXTERNAL_APPLE_CLIENT_ID, GOTRUE_EXTERNAL_APPLE_SECRET
```

### Edge Functions (Docker Compose)

```
SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_ENVIRONMENT,
SUPABASE_NETWORK, PORT
```

### GitHub Actions (Secrets)

```
APPLE_TEAM_ID, BUILD_CERTIFICATE_BASE64, P12_PASSWORD,
PROVISIONING_PROFILE_BASE64, PROVISIONING_PROFILE_NAME, KEYCHAIN_PASSWORD,
ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY,
SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL,
COOLIFY_WEBHOOK_URL, COOLIFY_API_TOKEN, EDGE_FUNCTIONS_HEALTH_URL
```

### iOS Build (xcconfig)

```
SUPABASE_URL, SUPABASE_ANON_KEY, PRODUCT_BUNDLE_IDENTIFIER
```
