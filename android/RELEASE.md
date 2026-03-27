# Wellvo Android — Release Guide

## Version Strategy

- **versionName**: Semantic versioning `MAJOR.MINOR.PATCH` (e.g., `1.0.0`)
  - `MAJOR` — Breaking changes, major redesigns
  - `MINOR` — New features, notable improvements
  - `PATCH` — Bug fixes, small tweaks
- **versionCode**: Monotonically increasing integer. Must increment on every Play Store upload.
  - Convention: `MAJOR * 10000 + MINOR * 100 + PATCH` (e.g., `1.0.0` → `10000`, `1.2.3` → `10203`)
  - For hotfixes within the same version, add 1 to the computed value

Both values are set in `app/build.gradle.kts` under `defaultConfig`.

## Release Signing

### Initial Keystore Generation (one-time)

```bash
keytool -genkeypair \
  -alias wellvo-release \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -keystore wellvo-release.jks \
  -storepass <STORE_PASSWORD> \
  -keypass <KEY_PASSWORD> \
  -dname "CN=Wellvo, O=Pearson Media LLC, L=City, ST=State, C=US"
```

**DO NOT** commit the keystore file. Store it securely (e.g., 1Password, Google Cloud Secret Manager).

### Configuration

Set these in `local.properties` (local dev) or environment variables (CI):

```properties
KEYSTORE_PATH=/path/to/wellvo-release.jks
KEYSTORE_PASSWORD=<store_password>
KEY_ALIAS=wellvo-release
KEY_PASSWORD=<key_password>
```

The `signingConfigs.release` block in `app/build.gradle.kts` reads from `local.properties` first, falling back to env vars. If no release keystore is configured, the build falls back to the debug signing key.

### Play App Signing

Enroll in [Play App Signing](https://play.google.com/console/about/app-signing/) (recommended). Google manages the app signing key; you upload with an upload key. If the upload key is compromised, Google can issue a new one without affecting existing users.

## Building a Release

```bash
cd android
./gradlew assembleRelease
```

The signed APK is output to `app/build/outputs/apk/release/app-release.apk`.

For AAB (required for Play Store):

```bash
./gradlew bundleRelease
```

Output: `app/build/outputs/bundle/release/app-release.aab`.

## Play Store Listing Assets

Located in `playstore-graphics/`:

| Asset | Size | File |
|-------|------|------|
| App icon (hi-res) | 512x512 | `icon-512.png` |
| Feature graphic | 1024x500 | `feature-graphic.png` |

Additional required assets (create manually or via screenshot tool):
- Phone screenshots: 2-8 images, 16:9 or 9:16, min 320px, max 3840px
- 7" tablet screenshots (optional): same requirements
- 10" tablet screenshots (optional): same requirements

## Pre-Release Checklist

- [ ] Increment `versionCode` and `versionName` in `app/build.gradle.kts`
- [ ] Verify `SUPABASE_URL` and `SUPABASE_ANON_KEY` point to production
- [ ] Verify `GOOGLE_WEB_CLIENT_ID` is set for production
- [ ] Replace placeholder `google-services.json` with production Firebase config
- [ ] Run `./gradlew test` — all tests pass
- [ ] Run `./gradlew bundleRelease` — build succeeds
- [ ] Test the release build on a physical device
- [ ] Test ProGuard: sign-in, check-in, push notifications, billing all work
- [ ] Upload AAB to Play Console (internal test track first)
