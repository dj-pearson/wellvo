# iOS Privacy Manifest — SDK Status Checklist

**Purpose.** Apple requires every iOS app submitted to App Store Connect to
include a `PrivacyInfo.xcprivacy` file. Additionally, every third-party SDK on
Apple's **commonly-used SDKs list** must ship its own manifest **and** be
code-signed. If any dependency is missing its manifest or signature, App Store
Connect will block the upload with an `ITMS-91061` / `ITMS-91065` error.

This file is the standing record of which SDKs we depend on, which have
shipped a manifest, and what follow-up is required before the next release.

Last verified: 2026-04-13.

---

## App-level manifests (owned by us)

| Target | Path | Status |
|---|---|---|
| Main app | `ios/DailyOK/PrivacyInfo.xcprivacy` | ✅ Committed |
| Notification Service Extension | `ios/DailyOKNotificationService/PrivacyInfo.xcprivacy` | ✅ Committed |

**Xcode wiring (must be done once, per target):**

1. Open `ios/DailyOK.xcodeproj` in Xcode.
2. For each target:
   - Select the target → **Build Phases** → **Copy Bundle Resources**.
   - Click **+** and add the `PrivacyInfo.xcprivacy` for that target.
3. Archive a release build (**Product → Archive**).
4. In the Organizer window, right-click the archive → **Generate Privacy
   Report**. Verify every declared data type and reason code appears.
5. Compare the generated report against the App Store Connect **App Privacy**
   answers. They must match exactly.

---

## Third-party iOS SDK status

These are the packages declared in `ios/DailyOK/Package.swift`. Each row
tracks whether the SDK ships a privacy manifest at the version we pin.

| SDK | Purpose | Ships `PrivacyInfo.xcprivacy`? | Code-signed? | Notes |
|---|---|---|---|---|
| `supabase-swift` | Auth, database, realtime | ✅ (since 2.3.x) | ✅ | Verify at bump; manifest is inside the built `.xcframework`. |
| `TelemetryDeck/SwiftSDK` | Aggregate hashed analytics | ✅ (since 2.1.x) | ✅ | No configuration required; SDK one-way hashes the user identifier before send. Initialized in release builds only (`#if !DEBUG`). |

> **Historical note — PostHog.** The iOS project briefly pulled in
> `posthog-ios`, but the SDK was never imported or initialized in Swift
> code. It was removed from `Package.swift` and `project.pbxproj` on
> 2026-04-13 to eliminate the unused compliance surface. If PostHog (or
> any similar product-analytics SDK) is ever added back, the Privacy
> Policy sub-processor list and the Google Play Data safety form both
> need to be updated in the same commit, and the SDK must be configured
> with session replay off and the EU host (`eu.i.posthog.com`).

**Verification command (run locally when bumping SDK versions):**

```bash
# Generate a privacy report after an archive. Xcode 15.2+ required.
xcodebuild -exportArchive \
  -archivePath build/DailyOK.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/Export

# After Export, Xcode prints any SDK missing a manifest. Treat warnings as
# blocking — App Store Connect treats them as blocking at upload time.
```

---

## Required-Reason APIs declared

Declared in `ios/DailyOK/PrivacyInfo.xcprivacy`:

| API category | Reason code | Why we use it |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Read/write app-owned `UserDefaults`. Triggered by Supabase SDK, StoreKit, and our own settings. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Display "last check-in at…" timestamps from on-device files. Also called transitively by `URLSession` cache logic. |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | Measure elapsed time between in-session events (rate-limit bookkeeping, retry back-off). Called transitively by Network framework. |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | Check free disk space before writing offline check-in cache. Called transitively by `URLSession` download tasks. |

**Audit cadence.** Before every App Store submission, re-verify each of the
four above is actually used (either by our own code or by a linked SDK). If
one is no longer used, remove it — Apple prefers a narrow list.

---

## Android — Google Play Data safety

Android does not use Apple's manifest format. The equivalent is the **Data
safety** form in the Google Play Console. Keep it in sync with:

- `/home/user/wellvo/website/src/pages/Privacy.tsx`
- `android/app/src/main/AndroidManifest.xml` permission declarations
- The in-app prominent-disclosure dialog for location

### Third-party Android SDK status

| SDK | Purpose | Notes |
|---|---|---|
| `supabase-kt` (auth, postgrest, realtime, functions) | Backend | No cross-app tracking; declare under "Personal info / User IDs" and "App activity". |
| `ktor-client-okhttp` | HTTP | No data collection. |
| `firebase-messaging` | Push (FCM) | Declare "Device or other IDs" (the FCM registration token). Google auto-populates some fields; review before submit. |
| `play-services-location` | Foreground / background location | Declare "Approximate location", Optional. Requires runtime permission + prominent disclosure. |
| `billing-ktx` | In-app billing | Declare "Purchase history" if you surface it — we do. Payment card data is never seen by the app. |
| `room-runtime`, `sqlcipher`, `security-crypto` | On-device storage | No data collection. Used for encrypted local cache. |
| `credentials` / `credentials-play-services-auth` / `googleid` | Sign in with Google | Declare collection of email and name via Google Sign-In. |
| `telemetry-deck` | Aggregate hashed analytics | Identifiers hashed before send; declare "App activity / App interactions" with purpose Analytics. |

---

## Change log

- **2026-04-13** — Initial manifest added for both iOS targets. TelemetryDeck
  added to the Privacy Policy sub-processor list after the audit found it in
  `Package.swift` and `build.gradle.kts` but not previously disclosed.
  `posthog-ios` was declared in `Package.swift` and linked in the Xcode
  project, but a source-level audit showed it was never imported or
  initialized — so it was removed in the same pass rather than disclosed.

---

## When to update this file

- Any time a new Swift Package is added or removed from `ios/DailyOK/Package.swift`.
- Any time a new dependency is added or removed from `android/app/build.gradle.kts`.
- Whenever Apple publishes a new required-reason API category or code.
- Before every App Store submission, as a final cross-check.
