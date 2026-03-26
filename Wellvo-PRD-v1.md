# WELLVO — Daily Check-In

## Product Requirements Document

**Version 1.0 | March 2026**
**Pearson Media LLC**
**Platform:** iOS (Swift Native) | **Backend:** Self-Hosted Supabase

---

## 1. Executive Summary

Wellvo is a daily check-in app that gives families peace of mind. One person (the "Owner") manages the account and sends check-in requests. Their connected family members ("Receivers") see a single, distraction-free screen with one button: "I'm OK." If a Receiver doesn't check in within the configured window, the Owner gets an escalating alert chain.

The app targets two primary markets: adult children monitoring aging parents, and parents keeping tabs on teenagers. Both share the same core anxiety — "Are they okay?" — and the same willingness to pay for peace of mind.

The business model is Owner-pays: the subscription lives on the Owner's account and includes two Receivers by default. Additional Receivers can be added as subscription add-ons. Receivers never pay or see billing.

---

## 2. Product Overview

| Attribute | Detail |
|-----------|--------|
| App Name | Wellvo |
| Tagline | "One tap. Total peace of mind." |
| Platform | iOS (Swift native, SwiftUI) |
| Backend | Self-hosted Supabase (PostgreSQL, Auth, Realtime, Edge Functions, Push via APNs) |
| Target Users | Adult children with aging parents; parents of teenagers |
| Monetization | Subscription (Owner-pays), includes 2 Receivers, add-on pricing for additional |
| MVP Timeline | 6–8 weeks |

---

## 3. User Roles & Experiences

### 3.1 Owner (Monitor)

The Owner is the person who pays, manages the family group, and controls all notification settings. This is typically an adult child watching over parents, or a parent watching over teenagers.

**Owner Capabilities:**

- Invite and remove Receivers via phone number or invite link
- Set unique check-in schedules per Receiver (time of day, frequency, timezone)
- Send on-demand "Check on you" push notifications to any Receiver at any time
- Configure escalation chain: how long to wait before reminder, second reminder, and Owner alert
- View real-time dashboard showing check-in status for all Receivers
- View check-in history, streaks, and time-of-check-in trends per Receiver
- Manage subscription, add/remove Receiver slots
- Set quiet hours (no notifications sent during these windows)
- Add additional family members as Viewer-only (can see dashboard but cannot modify settings)

### 3.2 Receiver (Check-In Person)

The Receiver experience is intentionally minimal. The app must be usable by someone with limited tech literacy, cognitive decline, or a teenager who will only engage if it takes zero effort.

**Receiver Experience:**

- Opens app to a single, full-screen "I'm OK" button — no navigation, no menus, no feeds
- Receives push notification at scheduled time: "Good morning! Tap to let your family know you're OK."
- Can respond directly from the push notification (actionable notification) without opening the app
- After tapping, sees a green confirmation: "Your family knows you're OK" with a checkmark animation
- Can optionally add a one-tap mood indicator (happy / neutral / tired) — shown on Owner dashboard
- Receives on-demand check-in requests from Owner with a gentle push: "[Name] is checking on you"
- No access to settings, billing, or other users' data
- App uses extra-large fonts, high contrast, and minimal UI elements for accessibility

### 3.3 Viewer (Read-Only Family Member)

Viewers are additional family members (siblings, extended family) who want visibility but don't need control. They see the same dashboard as the Owner but cannot modify settings, send check-in requests, or manage Receivers. This role exists to support the common dynamic where one sibling is the primary caregiver but others want peace of mind too.

---

## 4. Core Features

### 4.1 Check-In System

The check-in system is the heartbeat of the app. It has two modes:

**Scheduled Check-Ins:** The Owner sets a daily check-in time per Receiver. At that time, the Receiver gets a push notification. If they don't respond within the configured grace period, the escalation chain begins.

**On-Demand Check-Ins:** The Owner can tap "Check on [Name]" at any time from the dashboard. The Receiver immediately receives a push notification. If no response within the configured window, the Owner is alerted.

### 4.2 Escalation Chain

The escalation chain is fully configurable per Receiver by the Owner:

| Step | Default Timing | Action | Configurable |
|------|---------------|--------|-------------|
| 1 | T+0 min | Initial push notification to Receiver | Time of day, message text |
| 2 | T+30 min | Second push + sound alert to Receiver | Wait time (15–120 min) |
| 3 | T+60 min | Alert to Owner via push + optional SMS | Wait time, SMS toggle |
| 4 | T+90 min | Alert to all Viewers in the family group | Wait time, enable/disable |

The Owner can also configure a "critical alert" mode for Step 3+ that bypasses Do Not Disturb on their device (using iOS Critical Alerts entitlement).

### 4.3 Owner Dashboard

The dashboard is the Owner's primary screen. It shows:

- Status cards for each Receiver: name, current status (Checked In / Pending / Missed), time of last check-in, current streak
- Quick-action button per Receiver: "Check on [Name]" for on-demand pings
- Today's timeline: visual timeline showing when each Receiver checked in
- Weekly summary: check-in consistency percentage, average check-in time, mood trends (if mood indicator enabled)
- Pattern alerts: automatic flags when a Receiver's check-in time shifts significantly (e.g., normally checks in at 8am, suddenly checking in at 11am for a week)

### 4.4 Check-In History & Insights

Per-Receiver history view showing:

- Calendar heatmap of check-ins (green = on time, yellow = late, red = missed)
- Average check-in time trend line over 30/60/90 days
- Longest streak and current streak
- Mood trend chart (if enabled)
- Exportable report (PDF) for sharing with healthcare providers or family meetings

### 4.5 Push Notification System

Push notifications are the primary interaction mechanism for Receivers and are critical to the product. The system must support:

- Actionable notifications: Receiver can tap "I'm OK" directly from the notification without opening the app
- Scheduled delivery: Notifications sent at exact configured time per Receiver's timezone
- On-demand delivery: Instant push when Owner taps "Check on [Name]"
- Escalation notifications: Progressively urgent notifications through the chain
- Critical Alerts (iOS): Optional bypass of Do Not Disturb for Owner alerts on missed check-ins
- Notification sound customization: gentle tone for routine check-ins, urgent tone for escalations
- Delivery confirmation: backend tracks whether notification was delivered and opened

### 4.6 Family Group Management

The Owner has full control over the family group:

- Invite Receivers via SMS invite link or QR code
- Invite Viewers via same mechanism (separate role assignment)
- Remove any member from the group
- Transfer Owner role to another family member
- View which Receivers have the app installed and notifications enabled
- Re-send setup reminders to Receivers who haven't completed onboarding

---

## 5. Subscription & Monetization

### 5.1 Pricing Tiers

| Tier | Price | Includes | Features |
|------|-------|----------|----------|
| Free | $0 | 1 Receiver | Basic daily check-in, single scheduled time, push notifications, 7-day history |
| Family | $4.99/mo or $39.99/yr | 2 Receivers + 2 Viewers | Custom schedules, on-demand check-ins, full escalation chain, mood tracking, 90-day history, pattern alerts |
| Family+ | $7.99/mo or $59.99/yr | 5 Receivers + 5 Viewers | All Family features + Critical Alerts, exportable reports, unlimited history, priority support |
| Add-On Receiver | +$1.99/mo each | +1 Receiver slot | Available on Family or Family+ tiers |
| Add-On Viewer | +$0.99/mo each | +1 Viewer slot | Available on Family or Family+ tiers |

### 5.2 Billing Architecture

- All billing runs through the Owner's Apple ID via StoreKit 2 / App Store subscriptions
- Receivers and Viewers never see pricing, billing, or subscription screens
- Subscription status synced to Supabase via App Store Server Notifications V2
- Grace period: 7 days after subscription lapse before Receivers lose check-in functionality
- Downgrade handling: if Owner drops from Family+ to Family, excess Receivers are soft-deactivated with a prompt to choose which 2 to keep

---

## 6. Technical Architecture

### 6.1 iOS App (Swift Native)

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI (iOS 16+ minimum deployment target) |
| Architecture | MVVM with Swift Concurrency (async/await) |
| Push Notifications | APNs via Supabase Edge Functions + apple/swift-nio |
| Subscriptions | StoreKit 2 (Transaction, Product, subscription status) |
| Auth | Supabase Auth (email/password + Apple Sign-In) |
| Networking | Supabase Swift SDK (supabase-swift) |
| Local Storage | SwiftData for offline check-in queuing |
| Analytics | PostHog iOS SDK or TelemetryDeck (privacy-first) |
| Minimum iOS | iOS 16.0 |

### 6.2 Backend (Self-Hosted Supabase)

| Component | Detail |
|-----------|--------|
| Hosting | Contabo VPS via Coolify |
| Database | PostgreSQL 15+ (Supabase bundled) |
| Auth | Supabase Auth with Apple Sign-In provider, email/password |
| Realtime | Supabase Realtime for live dashboard updates |
| Edge Functions | Deno-based: push notification dispatch, escalation scheduler, subscription webhook handler |
| Push Delivery | APNs HTTP/2 via Edge Functions (using jose for JWT signing) |
| Scheduling | pg_cron for recurring check-in triggers + escalation timers |
| Storage | Supabase Storage for profile photos (optional) |
| CDN/DNS | Cloudflare |

### 6.3 Database Schema (Core Tables)

**users**
`id` (uuid, PK), `email`, `phone`, `display_name`, `role` (owner|receiver|viewer), `avatar_url`, `timezone`, `created_at`, `updated_at`

**families**
`id` (uuid, PK), `name`, `owner_id` (FK users), `subscription_tier`, `subscription_status`, `subscription_expires_at`, `max_receivers`, `max_viewers`, `created_at`

**family_members**
`id` (uuid, PK), `family_id` (FK families), `user_id` (FK users), `role` (owner|receiver|viewer), `status` (active|invited|deactivated), `invited_at`, `joined_at`

**receiver_settings**
`id` (uuid, PK), `family_member_id` (FK family_members), `checkin_time` (time), `timezone`, `grace_period_minutes`, `reminder_interval_minutes`, `escalation_enabled`, `quiet_hours_start`, `quiet_hours_end`, `mood_tracking_enabled`, `is_active`

**checkins**
`id` (uuid, PK), `receiver_id` (FK users), `family_id` (FK families), `checked_in_at` (timestamptz), `mood` (happy|neutral|tired|null), `source` (app|notification|on_demand), `scheduled_for` (timestamptz)

**checkin_requests**
`id` (uuid, PK), `family_id` (FK families), `receiver_id` (FK users), `requested_by` (FK users), `type` (scheduled|on_demand), `status` (pending|checked_in|missed|expired), `created_at`, `responded_at`, `escalation_step` (int), `next_escalation_at` (timestamptz)

**push_tokens**
`id` (uuid, PK), `user_id` (FK users), `token` (text), `platform` (ios), `is_active`, `created_at`, `updated_at`

**notification_log**
`id` (uuid, PK), `user_id` (FK users), `checkin_request_id` (FK), `type` (checkin_reminder|escalation|owner_alert|viewer_alert), `sent_at`, `delivered_at`, `opened_at`, `status` (sent|delivered|opened|failed)

### 6.4 Key RLS Policies

- Owners can read/write all family_members, receiver_settings, and checkin data for their family
- Receivers can only read their own receiver_settings and write their own checkins
- Viewers can read checkins and receiver status for their family, but cannot write anything
- Push tokens are only readable/writable by the owning user
- Subscription data is only writable by Edge Functions (service role), readable by Owner

### 6.5 Edge Functions

- **send-checkin-notification:** Triggered by pg_cron at each Receiver's scheduled time. Sends APNs push with actionable notification category.
- **process-checkin-response:** Receives check-in from app or notification action. Updates checkin_requests status, cancels escalation timer.
- **escalation-tick:** Runs every minute via pg_cron. Checks for pending checkin_requests past their next_escalation_at. Advances escalation step and sends appropriate notification.
- **on-demand-checkin:** Called by Owner via app. Creates checkin_request and immediately sends push to Receiver.
- **subscription-webhook:** Handles App Store Server Notifications V2. Updates family subscription status, tier, and receiver limits.
- **invite-receiver:** Generates invite link/code, creates pending family_member record, optionally sends SMS via Twilio or Amazon SNS.

---

## 7. Onboarding Flows

### 7.1 Owner Onboarding

1. Download app, create account (Apple Sign-In or email)
2. "Who do you want to check on?" — select: Aging Parent / Teenager / Other
3. Create family group with a name (e.g., "The Pearson Family")
4. Add first Receiver: enter their name, phone number, and preferred check-in time
5. App sends SMS invite link to Receiver's phone
6. Owner sees dashboard with Receiver in "Invited" status
7. Prompt to enable notifications and choose subscription tier

### 7.2 Receiver Onboarding

1. Receive SMS: "[Owner Name] wants to make sure you're OK every day. Tap to set up Wellvo."
2. Tap link → App Store download (or opens app if installed)
3. Open app → auto-links to family via invite token in deep link
4. Single screen: "Every day at [time], we'll send you a notification. Just tap 'I'm OK' and that's it."
5. Grant notification permission (with clear, non-technical explanation of why)
6. Done. App shows the "I'm OK" button. No further setup required.

---

## 8. UI/UX Specifications

### 8.1 Receiver App UI

The Receiver app is a single-screen experience. Design principles: maximum readability, zero cognitive load, works for ages 13–95.

- Full-screen layout with a single circular "I'm OK" button centered on screen, minimum 200pt diameter
- Button color: calm green (#2ECC71) with subtle pulse animation when a check-in is pending
- After tap: button transitions to a checkmark with "Your family knows you're OK" text, remains green for the rest of the day
- Optional mood selector appears briefly after check-in: three large emoji-style buttons (happy / neutral / tired), dismissible
- Dynamic Type support: all text respects iOS accessibility text size settings
- VoiceOver fully supported: button reads "Tap to check in and let your family know you're okay"
- No navigation bar, no tab bar, no hamburger menu, no settings accessible to Receiver
- Dark mode supported with same high-contrast design
- If check-in already completed today: button shows checkmark state, non-interactive, with "You've already checked in today" text

### 8.2 Owner App UI

The Owner app has more depth but should still feel simple and calm, not clinical or medical.

**Dashboard Tab:** Card-based layout. Each Receiver gets a status card showing: name, profile photo, status badge (green checkmark / yellow clock / red exclamation), time of last check-in, current streak count, and a "Check on [Name]" quick-action button.

**History Tab:** Per-Receiver calendar heatmap and trend charts. Tappable days show details. Streak badges and insights.

**Family Tab:** Member management. Invite new members, change roles, remove members, transfer ownership. Shows notification/app status per member.

**Settings Tab:** Per-Receiver notification schedules, escalation chain configuration, quiet hours, subscription management, account settings.

---

## 9. Marketing & Positioning

### 9.1 Target Segments

**Primary — Adult Children with Aging Parents:** 53+ million Americans are caregivers for aging family members. The core anxiety is "I haven't heard from Mom today — is she okay?" Current solutions (medical alert pendants, smart home sensors) feel clinical and stigmatizing. Wellvo feels like family, not healthcare.

**Secondary — Parents of Teenagers:** Parents of 13–18 year olds who want a lightweight, non-invasive check-in that doesn't feel like surveillance. Positioned as the opposite of location tracking — just a daily "I'm good" that respects the teen's autonomy.

**Tertiary — Long-Distance Relationships/Roommates:** Anyone who wants a simple daily signal from someone they care about. College students and parents, military families, close friends living far apart.

### 9.2 Positioning Statement

"Wellvo is the simplest way to know your loved ones are okay. One tap. Every day. Total peace of mind."

### 9.3 Key Differentiators

- Not a medical device or health tracker — it's a family connection tool
- Receiver experience is one button, not an app to learn
- Owner controls everything — Receivers don't need to configure anything
- No location tracking, no microphone access, no surveillance feel
- Works for both elderly parents and teenagers — same core mechanic, different emotional positioning

### 9.4 Viral Loop

The product has a built-in viral loop at the family level. One sibling sets up a parent, then invites their 2–3 other siblings as Viewers. Each of those siblings then becomes an Owner for their own in-laws or teenagers. The product spreads family-by-family, not user-by-user. Word of mouth at family gatherings, group chats, and holidays is the primary growth driver.

---

## 10. MVP Scope & Phasing

### 10.1 Phase 1 — MVP (Weeks 1–8)

- Owner and Receiver roles (no Viewer yet)
- Owner dashboard with status cards and on-demand check-in
- Receiver single-button check-in screen
- Scheduled daily push notifications with actionable notification support
- Basic escalation chain (2 steps: reminder to Receiver, then alert to Owner)
- Invite flow via SMS deep link
- Apple Sign-In + email/password auth
- Free tier (1 Receiver) + Family tier ($4.99/mo, 2 Receivers) via StoreKit 2
- Basic check-in history (30 days, list view)
- Self-hosted Supabase backend with pg_cron scheduling

### 10.2 Phase 2 — Growth (Weeks 9–16)

- Viewer role with read-only dashboard
- Full escalation chain (4 steps with SMS fallback)
- Mood tracking with trend charts
- Calendar heatmap and streak system
- Pattern alerts (check-in time drift detection)
- Family+ tier with expanded Receiver/Viewer limits
- Add-on Receiver/Viewer billing
- Critical Alerts (iOS DND bypass) for missed check-ins
- Onboarding optimization based on drop-off data

### 10.3 Phase 3 — Expansion (Weeks 17–24)

- Passive monitoring mode (detect phone activity without requiring tap — for cognitive decline use cases)
- Exportable PDF reports for healthcare providers
- Android companion app (Receiver-only initially, then full)
- Apple Watch complication (one-tap check-in from wrist)
- Widgets for both Owner (status glance) and Receiver (check-in button on home screen)
- Siri Shortcuts integration ("Hey Siri, I'm okay")
- Multi-family support (one Owner managing parents AND teenagers in separate family groups)
- Caregiver-specific features (notes per Receiver, medication reminders, appointment tracking)

---

## 11. Success Metrics

| Metric | MVP Target (3 months) | Growth Target (6 months) |
|--------|----------------------|--------------------------|
| Owner D7 Retention | > 60% | > 70% |
| Receiver Daily Check-In Rate | > 75% | > 85% |
| Free-to-Paid Conversion | > 8% | > 12% |
| Monthly Churn (paid) | < 8% | < 5% |
| Avg Receivers per Owner | > 1.5 | > 2.2 |
| Organic Invites per Owner | > 1 Viewer invited | > 2 Viewers invited |
| MRR | $2,000 | $10,000 |

---

## 12. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Receiver doesn't enable/keep notifications | Core loop breaks entirely | Owner dashboard shows notification status per Receiver. App prompts re-enable. Onboarding emphasizes this step. |
| False alarm fatigue | Owner ignores alerts, defeats purpose | Smart escalation with configurable timing. Pattern-based suppression (e.g., Receiver always checks in late on weekends). |
| Apple notification delivery reliability | Missed check-ins due to iOS throttling | Use Time Sensitive notification interruption level. Implement delivery confirmation tracking. SMS fallback in Phase 2. |
| Receiver with cognitive decline can't use app | Loses the most vulnerable user segment | Phase 3 passive monitoring mode. Phase 2 Apple Watch tap. Keep UI radically simple. |
| Competitor enters with deeper pockets | Outspent on marketing | Family-level network effect is the moat. Each family's data and configuration creates switching cost. Focus on organic, word-of-mouth growth. |
| App Store subscription review delays | Delayed launch | Submit subscription IAP metadata early. Start with Free tier if needed, add paid post-approval. |

---

## 13. Competitive Landscape

Existing solutions fall into three categories, none of which nail the simplicity + family dynamic that Wellvo targets:

**Medical Alert Devices (Life Alert, Medical Guardian):** Hardware-based, expensive ($30–50/month), stigmatizing, designed for emergencies not daily connection. Target is 75+ with fall risk, not general aging-in-place or teenagers.

**Location Sharing (Life360, Find My):** Surveillance-heavy, privacy concerns, not designed for check-ins. Teenagers resist it. Elderly parents find it confusing. Doesn't answer "are they okay" — just "where are they."

**Smart Home Sensors (Lively, GrandCare):** Requires hardware installation, complex setup, expensive. Overkill for the core anxiety. Most families want a simple signal, not a sensor network.

Wellvo's positioning is deliberately between these categories: lighter than medical devices, more purposeful than location sharing, simpler than smart home, and cheaper than all three.

---

## 14. Appendix

### 14.1 App Store Metadata (Draft)

**App Name:** Wellvo — Daily Check-In
**Subtitle:** One tap. Peace of mind.
**Category:** Lifestyle (Primary), Health & Fitness (Secondary)
**Keywords:** check in, family safety, aging parents, daily check, senior safety, teen check in, family wellness, caregiver, peace of mind, elderly care

### 14.2 Critical iOS Entitlements Required

- Push Notifications (APNs)
- Sign in with Apple
- Critical Alerts (requires Apple approval — submit justification with medical/safety use case)
- Time Sensitive Notifications
- Background App Refresh (for offline check-in sync)

### 14.3 Privacy & Data Handling

- No location data collected (differentiator vs. Life360)
- No microphone or camera access
- Check-in data stored with encryption at rest in Supabase
- Data retention: configurable by Owner, default 1 year
- CCPA/GDPR compliant data export and deletion on request
- App Tracking Transparency: no third-party tracking SDKs
- Privacy Nutrition Label: minimal data collection footprint
