# Apple App Site Association (AASA) — US-IOS109

`apple-app-site-association` enables Universal Links so tapping a
`https://dailyok.net/invite/...` (or `/join/...`) link opens the Daily OK iOS
app instead of Safari. It must be served from
`https://dailyok.net/.well-known/apple-app-site-association` over HTTPS, with
`Content-Type: application/json` and **no** redirect.

## Before this works — manual steps that can't be done in code

1. **Fill the real Team ID.** Replace `TEAMID` in
   `apple-app-site-association` with the Apple Developer **Team ID** (the
   `AppIdentifierPrefix`, same value as the `APPLE_TEAM_ID` CI secret). The
   `appID` must be `<TeamID>.com.wellvo.ios` — note the **bundle id is
   `com.wellvo.ios`**, NOT the `dailyok.net` brand domain (see the brand-vs-id
   split in `CLAUDE.md`).
2. **Enable the Associated Domains capability** for App ID `com.wellvo.ios` in
   the Apple Developer portal and **regenerate the provisioning profiles** used
   by CI. Only then add to `ios/DailyOK/DailyOK.entitlements`:
   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
     <string>applinks:dailyok.net</string>
   </array>
   ```
   Adding that entitlement **before** the portal capability + profile exist will
   fail code signing, which is why it is intentionally not committed yet.
3. **Confirm `Content-Type`.** Cloudflare Pages serves `.well-known/*` from
   `public/`. Verify `website/public/_headers` sets
   `Content-Type: application/json` for `/.well-known/apple-app-site-association`.

## Critical Alerts entitlement

`com.apple.developer.usernotifications.critical-alerts` (in
`DailyOK.entitlements`, requested in `PushNotificationService`) requires a
**special Apple grant**. Confirm it is approved for `com.wellvo.ios` and that the
provisioning profile carries it, or installs/review will fail.
