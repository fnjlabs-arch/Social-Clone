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
Deactivated: 403 { "ok": false, "error": "code_deactivated",
               "message": "This code has been deactivated. Please check with your teacher." }
Expired: 403 { "ok": false, "error": "code_expired",
               "message": "This code has expired. Please check with your teacher." }
Unknown/invalid: 404 { "ok": false, "error": "invalid_code", "message": "..." }
```

## What the numbers mean (report fields)

`GET /api/v1/admin/report` (all codes) and `GET /api/v1/teacher/report`
(that teacher's codes only) return the same shape, plus `by_tier`:

- `issued` — every code ever generated in scope.
- `sold` — the SAME number as `issued`. Read this carefully: the
  dashboard tracks generation and redemption, NOT payments. Teachers buy
  codes in bulk upfront in this product, so a code issued to a teacher
  is a code sold — but this report is not a payment ledger, and it must
  never be presented as one.
- `activated` (alias `used`) — redeemed and bound to a device.
- `unused` — status `unused`, including expired-but-unused codes.
- `remaining` — status `unused` AND not expired: codes still usable.
- `deactivated` — admin-disabled codes (see below).
- `expired` — `expires_at` set and in the past, status unused or used.
  A deactivated code counts as deactivated, not expired.

## Code management (admin only)

`POST /api/v1/admin/licenses/:code/status` with
`{ "action": "deactivate" | "reactivate" }` (also buttons in the web UI's
Codes table, admin view only):

- **Deactivate:** an unused OR bound code becomes `deactivated`. Its
  old `device_id`/`redeemed_at` are kept for audit, but redeem is
  rejected with `code_deactivated` until reactivated. Deactivating an
  already-deactivated code is idempotent (200, current status).
- **Reactivate:** a `deactivated` code returns to `unused` with its
  device binding cleared, so it activates fresh on any device.
  Reactivating a code that is not deactivated is a 400
  (`not_deactivated`), not a silent no-op.
- **Expiry:** generation accepts an optional `expires_at` (epoch
  milliseconds or ISO date); omitted means the code never expires, as
  all codes did before. An expired code's redeem is rejected with
  `code_expired` — even on the device it bound to.
- **HONEST LIMIT — no instant remote kill:** the app does not phone home
  continuously, so deactivating a code does NOT instantly lock an
  already-activated device offline. It blocks (re)activation and any
  future redeem of that code. Do not promise a remote kill.

## App lockout (app-side, in the license code)

After 3 wrong code entries the app locks activation for 8 hours; a
further 3 wrong entries after that lock expires locks it for 24 hours,
and every further lock without an intervening successful activation is
also 24 hours. The state persists in secure storage (survives restarts).
A wrong entry is a malformed/offline-invalid code or a dashboard 404
`invalid_code`. Deactivated/expired rejections, 409 already-in-use, and
network errors NEVER count. While locked, the activation screen shows
the unlock time. A successful activation clears the whole lockout cycle.

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
  `POST /api/v1/admin/licenses/generate` `{ teacher_id, tier, count, expires_at? }`
  (count must be 10, 20 or 100; `expires_at` optional, epoch ms or ISO
  date, null = never expires), `GET /api/v1/admin/report`,
  `POST /api/v1/admin/licenses/:code/status` `{ action: "deactivate" | "reactivate" }`
- Teacher: `GET /api/v1/teacher/report`
- Logged in (either role): `GET /api/v1/licenses[?teacher_id=&status=]`
  (teachers always see only their own codes; `status` accepts
  `used`, `unused`, or `deactivated`; each row now includes `expires_at`)

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
mock of D1. **46/46 checks passed**, including: setup-once admin, wrong
password rejected, teacher creation + duplicate rejected, invalid batch size
rejected, SC5 ×10 and SC10 ×20 generation matching the Dart format and an
independently recomputed checksum, redeem on device A → activated,
same code on device B → 409 "already in use on another device",
same code again on device A → idempotent, unissued/malformed codes → 404,
teacher isolation (teacher 1 still sees only her 10 codes after teacher 2's
batch), reports (30 issued / 2 used / 28 remaining), plus the newer stats /
deactivate / reactivate / expiry checks: deactivate blocks redeem (unused
and bound codes), reactivate clears the binding for a fresh activation,
reactivating a non-deactivated code is a 400, teachers cannot deactivate,
expired codes are rejected with `code_expired` and counted separately,
and the final mixed report reads 50 issued/sold, 4 activated, 46 unused,
36 remaining, 0 deactivated, 10 expired.

## What is intentionally left for later

- **Deployment** (blocked — see above).
- **App-side integration:** `LicenseRepository.activate()` now POSTs
  `/api/v1/licenses/redeem` before persisting (plus the wrong-code
  lockout), keeping its offline fallback for when the network is
  unavailable — implemented in the app code, but NOT yet shipped: it
  ships in its own single APK build/test round once the Worker URL is
  set, and no APK build was dispatched here.
- **Qasim's single test round (after deployment):** open the Worker URL,
  create the admin account via first setup (choose the password yourself —
  never in chat), log in, create one teacher, generate 10 test codes,
  redeem one from a phone (device A), confirm a second device is rejected
  and the same device is idempotent, and check the report counts. Use
  obviously-test teacher names for that round; real saleable codes are only
  generated once the flow is confirmed.
