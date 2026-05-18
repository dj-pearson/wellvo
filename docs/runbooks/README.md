# Daily OK — Operational runbooks

Step-by-step procedures for recurring or emergency operational tasks. Each
runbook is self-contained; this index just tracks what exists and its cadence.

## Recurring tasks

| Runbook | Cadence | Owner | Why it matters |
| --- | --- | --- | --- |
| [Sign in with Apple `client_secret` rotation](../auth/sign-in-with-apple-rotation.md) | **Every 5 months** (hard expiry at 6 months) | Backend / ops | If the JWT expires, **all Sign-in-with-Apple logins fail silently**. A reminder issue is auto-opened 30 days before expiry by `.github/workflows/siwa-secret-expiry-reminder.yml`. |

## On-demand / emergency

_None documented yet. Add new runbooks under `docs/` and link them here with
their trigger and cadence._
