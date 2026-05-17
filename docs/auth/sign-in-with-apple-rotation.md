# Sign in with Apple — `client_secret` rotation runbook

Apple's "Sign in with Apple" provider uses a **JWT as the OAuth `client_secret`**.
That JWT is signed with a `.p8` private key and **expires in at most 6 months**
(Apple rejects anything longer). If it expires and is not rotated, **every
Sign-in-with-Apple login breaks silently** — users see a generic auth failure,
not an obvious "secret expired" message. This runbook is the rotation procedure.

> Rotation cadence: **every 5 months** (one month of safety margin before the
> 6-month hard expiry). The reminder automation in
> `.github/workflows/siwa-secret-expiry-reminder.yml` opens a tracking issue
> 30 days before the recorded expiry.

## Prerequisites

Gather these from the [Apple Developer portal](https://developer.apple.com/account):

| Item | Where to find it | Example |
| --- | --- | --- |
| **Team ID** | Membership page (top-right account) | `4G65K84G73` |
| **Key ID** | Certificates, Identifiers & Profiles → Keys → the Sign-in-with-Apple key | `AB12CD34EF` |
| **`.p8` key file** | Downloaded once when the key was created (`AuthKey_<KeyID>.p8`). **Apple does not let you re-download it** — it must be retrieved from the secure password manager / secrets vault, never from this repo. | `AuthKey_AB12CD34EF.p8` |
| **Service ID (`sub`)** | Identifiers → the Services ID configured for Sign in with Apple | `net.dailyok.app` |

> **Never commit the `.p8` key or the generated JWT.** `.gitignore` excludes
> `*.p8`, `*.p12`, `*.mobileprovision`, `*.cer`. Keep the `.p8` in the team
> password manager / secrets vault only.

## Step 1 — Generate the new `client_secret` JWT

Run this on a Mac or Linux machine that has the `.p8` file present locally
(scratch directory, **not** the repo). Requires Ruby with the `jwt` gem
(`gem install jwt`):

```ruby
# You need: Team ID, Key ID, Service ID, and the .p8 key file.
require 'jwt'
require 'openssl'

key = OpenSSL::PKey::EC.new(File.read('AuthKey_XXXXXXXXXX.p8'))
payload = {
  iss: 'YOUR_TEAM_ID',                 # e.g. 4G65K84G73
  iat: Time.now.to_i,
  exp: Time.now.to_i + 15_552_000,     # 6 months (Apple's maximum)
  aud: 'https://appleid.apple.com',
  sub: 'net.dailyok.app'               # the Services ID
}
puts JWT.encode(payload, key, 'ES256', { kid: 'YOUR_KEY_ID' })
```

Copy the printed token. Also note the `iat` and `exp` epoch seconds — you will
record them in Step 3.

## Step 2 — Paste it into Supabase Auth

1. Open the self-hosted Supabase **Studio → Authentication → Providers → Apple**
   (or edit the Auth config / GoTrue env if Studio is not exposed).
2. Set/replace:
   - **Client IDs**: the Services ID (`net.dailyok.app`) — unchanged on rotation.
   - **Secret Key (for OAuth)**: paste the **new JWT** from Step 1.
3. Save. Supabase picks up the new secret immediately for new sign-in attempts.
4. Smoke-test: perform a real Sign-in-with-Apple login from a debug build of the
   iOS app (and the website if SIWA is enabled there). Confirm a token is issued.

> The native iOS app itself does not hold this secret — it only sends Apple's
> identity token to Supabase, and Supabase exchanges it using this
> `client_secret`. So no app release is needed to rotate; this is a
> backend-only change.

## Step 3 — Record the rotation

Update [`docs/auth/last-rotated.txt`](./last-rotated.txt) with the `iat` and
`exp` you used (epoch seconds) and the date. Commit that file (it contains **no
secret** — only timestamps and the human who rotated). The expiry-reminder
GitHub Action reads `exp` from this file.

## Step 4 — Calendar reminder (belt and braces)

The GitHub Action is the primary reminder, but also add a personal/calendar
reminder as backup. Template:

```
Title:   Rotate Daily OK "Sign in with Apple" client_secret
When:    <exp date minus 30 days>
Repeat:  none (re-set each rotation from the new exp)
Notes:   Runbook: docs/auth/sign-in-with-apple-rotation.md
         If this lapses, ALL Sign-in-with-Apple logins fail silently.
         .p8 key lives in the team password manager, not the repo.
```

## What is intentionally NOT automated

The JWT signing itself is **not** run in CI, by design: it requires the `.p8`
private key, which must never live in a CI secret store or this repo. CI only
*reminds* (Step 4 / the workflow); a human performs Steps 1–3 with the key
pulled from the password manager.

## Failure mode reference

| Symptom | Likely cause |
| --- | --- |
| All new Sign-in-with-Apple logins fail; email/password still works | `client_secret` JWT expired (missed rotation) — do Steps 1–3 now |
| `invalid_client` from Apple during exchange | Wrong `sub` (Services ID), wrong `kid` (Key ID), or `.p8` does not match the Key ID |
| Worked, then broke exactly ~6 months later | Classic expiry — this runbook exists to prevent it |
