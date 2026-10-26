# Social Clone — License Dashboard

**Status (2026-10-26): code complete and locally verified; NOT yet deployed
to Cloudflare — see "Deployment status" below. Do not treat the Worker URL
as live until deployment succeeds.**

## What it is

Cloudflare Workers + D1 (free tier) dashboard for Social Clone licenses.
"Powered by SadSha", as the app is. The Flutter app is untouched — app-side
integration is a later, separate step (see below).

- **Admin (Qasim/Mili):** create teacher accounts; generate license codes in
  bulk (10 / 20 / 100 at a time); see every code, its status, and reports.
- **Teacher:** log in, see only their own codes, code status
  (unused / used / bound device), and their own issued/used/remaining report.
- **Device binding:** a code redeems once and binds to that device. The same
  code on another device is rejected; re-pasting on the same device is
  idempotent (no second activation).

## Code format (must match the app)

From `apps/weblibre/lib/features/license/domain/license_code.dart`:

- SC5: `SC5-` + 22 random chars + 4 checksum chars = **30** total, 5 profiles.
- SC10: `SC10-` + 31 random chars + 4 checksum chars = **40** total, 10 profiles.
- Alphabet: `ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*`
  (no `I`, `O`, `i`, `l`, `o`, `0`, `1` — unambiguous characters only).
- Checksum: `sum(codeUnit * (index + 1))`, value `(sum % 1296) * 1296`,
  rendered as 4 base36 chars, most-significant first.

Generated codes are validated by the app's own offline check
(`validateLicenseCode`) before anything else happens.

## Redeem API contract

The app's `activate()` TODO names only the path —
`POST /api/v1/licenses/redeem` — with no request/response shape, so this
contract is the dashboard's own and app integration must use it as-is:

```
Request:  { "code": "SC5-...", "device_id": "<stable per-device id>" }
Success:  { "ok": true, "status": "activated" | "already_active_on_this_device",
            "tier": "SC5" | "SC10", "max_profiles": 5 | 10 }
Rejected: 409 { "ok": false, "error": "already_in_use",
               "message": "This code is already in use on another device." }
Unknown/invalid: 404 { "ok": false, "error": "invalid_code", "message": "..." }
```

`device_id` is whatever stable identifier the app chooses per device
(it is stored, never shown to other teachers). The endpoint is intentionally
unauthenticated — the app must be able to call it before any login — but
codes are unguessable (22/31 random chars from a 66-character alphabet).

## Other API endpoints (all JSON; login returns a Bearer session token)

- `GET /api/v1/setup/status` → `{ needs_setup: true|false }`
- `POST /api/v1/setup` `{ username, password }` — works **only while no
  admin exists**; creates the first admin. Passwords need 8+ characters and
  are stored only as PBKDF2-SHA-256 hashes (salted, 100,000 iterations).
  Sessions expire after 7 days.
- `POST /api/v1/auth/login` `{ username, password }` → `{ token, role }`
- `POST /api/v1/auth/logout`
- Admin only: `POST /api/v1/admin/teachers`, `GET /api/v1/admin/teachers`,
  `POST /api/v1/admin/licenses/generate` `{ teacher_id, tier, count }`
  (count must be 10, 20 or 100), `GET /api/v1/admin/report`
- Teacher: `GET /api/v1/teacher/report`
- Logged in (either role): `GET /api/v1/licenses[?teacher_id=&status=]`
  (teachers always see only their own codes)

## Deployment status — READ THIS FIRST

**Blocked on token scope, not on code.** The existing "Mili Deploy QS"
token on Qasim's own Cloudflare account carries only Pages Edit, Zone DNS
Edit and Zone Zone Read. Verified 2026-10-26 against account
`7cbeb5df29e2e556f149aa8fded5804c`:

- Workers script upload: **403 "No access to the specified resource."**
- D1 database list and create: **401, code 10000, "Authentication error"**
- KV namespaces list: **401, same error**
- Pages projects list: works (the token's real scope).

No Worker was created, no D1 database was created, and nothing was deployed
to any other account. The probe script name used during testing was never
created server-side (its PUT was rejected).

**Unblocker (free, same account, no purchase):** in Qasim's own Cloudflare
dashboard, edit the token (or create a new token on the same account) to
add **Workers Edit** and **D1 Edit** scopes. Then deploy (below) — no paid
Workers/D1 plan is needed; both stay on the free tier, and no custom domain
is attached (the Worker runs on its free `*.workers.dev` address).

## Deploy (after the unblocker)

```bash
cd dashboard
# 1. Create the D1 database (free tier) and put its ID in wrangler.toml
wrangler d1 create social-clone-dashboard
wrangler d1 execute social-clone-dashboard --file=schema.sql
# 2. Deploy the Worker
wrangler deploy
# The Worker URL printed by wrangler is the dashboard URL.
```

Or, via the Cloudflare REST API with a suitably scoped token: create the D1
database, apply `schema.sql` through the D1 query endpoint, then upload the
Worker script with a `d1_databases` binding pointing at that database.

## Local verification (done 2026-10-26, no Cloudflare involved)

`node test-local.mjs` runs the real Worker code against an in-memory SQLite
mock of D1. **25/25 checks passed**, including: setup-once admin, wrong
password rejected, teacher creation + duplicate rejected, invalid batch size
rejected, SC5 ×10 and SC10 ×20 generation matching the Dart format and an
independently recomputed checksum, redeem on device A → activated,
same code on device B → 409 "already in use on another device",
same code again on device A → idempotent, unissued/malformed codes → 404,
teacher isolation (teacher 1 still sees only her 10 codes after teacher 2's
batch), and reports (30 issued / 2 used / 28 remaining).

## What is intentionally left for later

- **Deployment** (blocked — see above).
- **App-side integration:** `LicenseRepository.activate()` must POST
  `/api/v1/licenses/redeem` (see contract above) before persisting, keeping
  its current offline fallback for when the network is unavailable. That
  change ships in its own single APK build/test round — it is NOT part of
  this dashboard build, and no APK build was dispatched here.
- **Qasim's single test round (after deployment):** open the Worker URL,
  create the admin account via first setup (choose the password yourself —
  never in chat), log in, create one teacher, generate 10 test codes,
  redeem one from a phone (device A), confirm a second device is rejected
  and the same device is idempotent, and check the report counts. Use
  obviously-test teacher names for that round; real saleable codes are only
  generated once the flow is confirmed.
