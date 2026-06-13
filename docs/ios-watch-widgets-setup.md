# iOS Watch + Widgets + Siri — Setup & Reconciliation

This document tracks the implementation of the Apple Watch and widget/Siri
slices (`US-IOS001–010`) and the Xcode steps that **must be done on a Mac**
because they can't be created/verified in the headless environment.

## Architecture: one shared check-in core

Every out-of-process surface (Siri/Shortcuts, the interactive widget, the iOS 18
Control Center control, and the watch) performs the **same** check-in through a
single, SDK-free core so they all behave identically and there is **no new
backend contract** — they call the existing `process-checkin-response` edge
function.

```
ios/DailyOK/Shared/                      ← link into app + widget + watch targets
  SharedAppGroup.swift                   App Group id + keys
  SharedCheckInState.swift               Codable snapshot + read/write store
  SharedCheckInClient.swift              URLSession check-in + token refresh (no Supabase SDK)
  CheckInIntent.swift                    App Intent used by Siri / widget / control / watch
  DailyOKAppShortcuts.swift              Siri phrases ("check in with Daily OK")

ios/DailyOK/Services/
  SharedCheckInPublisher.swift           app-only: mirrors the live Supabase session into the snapshot
```

The phone is the source of truth: `ReceiverViewModel.loadStatus()` republishes
the snapshot, `performCheckIn()` marks it done, and `AuthViewModel.signOut()`
clears it.

## Status

### Phase 1 — Siri / Shortcuts / Action Button (DONE, in app target)
- Shared check-in core + `CheckInIntent` + `DailyOKAppShortcuts`.
- Wired into the existing **DailyOK** app target in `project.pbxproj`.
- App Group `group.com.wellvo.ios` added to `DailyOK.entitlements`.
- Delivers: "Hey Siri, check in with Daily OK", a Shortcuts action, and an
  Action Button assignment — all without opening the app. (`US-IOS008`, and the
  intent half of `US-IOS010`.)

### Phase 2 — Interactive Home/Lock Screen widget (`US-IOS006`) + Control (`US-IOS010`)
Requires a **Widget Extension target** (see "Create in Xcode" below).

### Phase 3 — Apple Watch app (`US-IOS001/002`, complications `US-IOS004`)
Requires a **watchOS App target** + WatchConnectivity (see below).

## ⚠️ Reconcile in Xcode (cannot be done headlessly)

1. **The repo `project.pbxproj` is hand-maintained and partially stale.** The
   `DailyOKNotificationService/` extension exists on disk but is **not** a target
   in `project.pbxproj`, and the App Group entitlement was missing from the main
   app. Open the project in Xcode and confirm the real target graph matches.
   If Xcode regenerates the project, re-apply the Phase 1 file memberships.

2. **App Group capability** must be enabled (Signing & Capabilities) on the app,
   the notification extension, the widget extension, and the watch app — all
   using `group.com.wellvo.ios`.

3. **Verify `Session.expiresAt`** in the installed supabase-swift version. The
   publisher assumes it is a unix `TimeInterval`
   (`Date(timeIntervalSince1970: session.expiresAt)`). If the SDK exposes it as a
   `Date`, drop the wrapper.

4. **Test Siri/Shortcuts**: build to a device, open the app once (so intents are
   indexed), then try "Hey Siri, check in with Daily OK" and the Shortcuts app.

### Create in Xcode — Widget Extension (Phase 2)
- File ▸ New ▸ Target ▸ **Widget Extension**, name `DailyOKWidgets`, include
  "Include Live Activity" off (for now), App Group on.
- Add the `ios/DailyOK/Shared/*.swift` files to the widget target's membership.
- Bundle id suggestion: `com.wellvo.ios.widgets`.

### Create in Xcode — watchOS App (Phase 3)
- File ▸ New ▸ Target ▸ **Watch App** (SwiftUI), name `DailyOK Watch App`.
- Add the `ios/DailyOK/Shared/*.swift` files to the watch target's membership.
- Enable App Group; add WatchConnectivity plumbing (phone ↔ watch snapshot sync).
- Bundle id suggestion: `com.wellvo.ios.watchkitapp`.
