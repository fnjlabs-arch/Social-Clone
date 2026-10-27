// Social Clone — License Dashboard Worker (Cloudflare Workers + D1, free tier).
//
// Serves: a phone-usable web UI for admin + teachers, and the JSON API the
// Flutter app will call at activation time (see POST /api/v1/licenses/redeem).
// No secrets live in this file. Teacher/admin passwords are stored only as
// PBKDF2 hashes in D1. The first admin account is created by the operator
// via POST /api/v1/setup, which works only while no admin exists.
//
// Code format — copied exactly from the app
// (apps/weblibre/lib/features/license/domain/license_code.dart):
//   SC5:  "SC5-"  + 22 random chars + 4 checksum chars = 30 total
//   SC10: "SC10-" + 31 random chars + 4 checksum chars = 40 total
// Checksum: sum over body chars of codeUnit * (index + 1); value =
// (sum % 1296) * 1296, rendered as 4 base36 chars, most-significant first.

const CODE_ALPHABET =
  'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*';
const CHECKSUM_ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const TIERS = {
  SC5: { prefix: 'SC5-', total: 30, randomLen: 22, maxProfiles: 5 },
  SC10: { prefix: 'SC10-', total: 40, randomLen: 31, maxProfiles: 10 },
};
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function checksumFor(body) {
  let sum = 0;
  for (let i = 0; i < body.length; i++) sum += body.charCodeAt(i) * (i + 1);
  let value = (sum % 1296) * 1296;
  const chars = [];
  for (let i = 0; i < 4; i++) {
    chars.push(CHECKSUM_ALPHABET[value % 36]);
    value = Math.floor(value / 36);
  }
  return chars.reverse().join('');
}

function randomChars(n) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  let out = '';
  for (const b of bytes) out += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return out;
}

export function makeCode(tierKey) {
  const tier = TIERS[tierKey];
  if (!tier) throw new Error('unknown tier');
  const body = tier.prefix + randomChars(tier.randomLen);
  return body + checksumFor(body);
}

// Port of the app's validateLicenseCode(): returns the tier key or null.
export function validateCode(raw) {
  if (typeof raw !== 'string') return null;
  const code = raw.trim();
  for (const [key, tier] of Object.entries(TIERS)) {
    if (!code.startsWith(tier.prefix)) continue;
    if (code.length !== tier.total) return null;
    const body = code.slice(0, tier.total - 4);
    const checksum = code.slice(tier.total - 4);
    if (checksum !== checksumFor(body)) return null;
    const randomPart = body.slice(tier.prefix.length);
    for (const c of randomPart) if (!CODE_ALPHABET.includes(c)) return null;
    return key;
  }
  return null;
}

// ---- crypto helpers (WebCrypto; also available in Node 24 for tests) ----
const enc = new TextEncoder();
function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function unhex(s) {
  const bytes = new Uint8Array(s.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(s.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}
async function hashPassword(password, saltHex) {
  const salt = saltHex ? unhex(saltHex) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    key,
    256,
  );
  return { salt: hex(salt), hash: hex(bits) };
}
function newToken() {
  return hex(crypto.getRandomValues(new Uint8Array(32)));
}

// ---- HTTP helpers ----
function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}
async function currentUser(env, request) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return null;
  const row = await env.DB.prepare(
    'SELECT s.user_id, s.expires_at, u.username, u.role FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?',
  )
    .bind(token)
    .first();
  if (!row || row.expires_at < Date.now()) return null;
  return { id: row.user_id, username: row.username, role: row.role };
}
async function requireRole(env, request, role) {
  const user = await currentUser(env, request);
  if (!user) return { error: json({ ok: false, error: 'unauthorized' }, 401) };
  if (role && user.role !== role) return { error: json({ ok: false, error: 'forbidden' }, 403) };
  return { user };
}

// ---- API handlers ----
async function handleSetup(env, request) {
  const { username, password } = await readJson(request);
  if (!username || !password || String(password).length < 8) {
    return json({ ok: false, error: 'username and a password of at least 8 characters are required' }, 400);
  }
  const existing = await env.DB.prepare("SELECT id FROM users WHERE role = 'admin' LIMIT 1").first();
  if (existing) return json({ ok: false, error: 'setup already complete' }, 403);
  const { salt, hash } = await hashPassword(String(password));
  const id = newToken().slice(0, 16);
  await env.DB.prepare(
    'INSERT INTO users (id, username, role, salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  )
    .bind(id, String(username).trim(), 'admin', salt, hash, Date.now())
    .run();
  return json({ ok: true, message: 'Admin account created. Log in with it.' });
}

async function handleLogin(env, request) {
  const { username, password } = await readJson(request);
  const user = await env.DB.prepare('SELECT * FROM users WHERE username = ?')
    .bind(String(username || '').trim())
    .first();
  if (!user) return json({ ok: false, error: 'invalid login' }, 401);
  const { hash } = await hashPassword(String(password || ''), user.salt);
  if (hash !== user.password_hash) return json({ ok: false, error: 'invalid login' }, 401);
  const token = newToken();
  await env.DB.prepare('INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)')
    .bind(token, user.id, Date.now() + SESSION_TTL_MS)
    .run();
  return json({ ok: true, token, username: user.username, role: user.role });
}

async function handleLogout(env, request) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (token) await env.DB.prepare('DELETE FROM sessions WHERE token = ?').bind(token).run();
  return json({ ok: true });
}

async function handleCreateTeacher(env, request) {
  const gate = await requireRole(env, request, 'admin');
  if (gate.error) return gate.error;
  const { username, password } = await readJson(request);
  if (!username || !password || String(password).length < 8) {
    return json({ ok: false, error: 'username and a password of at least 8 characters are required' }, 400);
  }
  const { salt, hash } = await hashPassword(String(password));
  const id = newToken().slice(0, 16);
  try {
    await env.DB.prepare(
      'INSERT INTO users (id, username, role, salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(id, String(username).trim(), 'teacher', salt, hash, Date.now())
      .run();
  } catch {
    return json({ ok: false, error: 'that username already exists' }, 409);
  }
  return json({ ok: true, id, username: String(username).trim() });
}

// Report counts — definitions (see README "What the numbers mean"):
//   issued      — every code ever generated in this scope.
//   sold        — same number as issued. The dashboard tracks generation
//                 and redemption, NOT payments; teachers buy codes in
//                 bulk upfront in this product, so a code issued to a
//                 teacher is a code sold. This is NOT payment tracking.
//   activated   — status 'used': redeemed and bound to a device.
//   unused      — status 'unused', including expired-but-unused codes.
//   remaining   — status 'unused' AND not expired: codes still usable.
//   deactivated — status 'deactivated' (admin-disabled).
//   expired     — expires_at set and in the past, status unused or used.
//                 A deactivated code counts as deactivated, not expired.
// `used` is kept as an alias of `activated` for the older report shape.
async function reportFor(env, teacherId) {
  const rows = await env.DB.prepare(
    'SELECT tier, status, expires_at FROM licenses ' +
      (teacherId ? 'WHERE teacher_id = ? ' : ''),
  )
    .bind(...(teacherId ? [teacherId] : []))
    .all();
  const now = Date.now();
  const report = {
    issued: 0, sold: 0, activated: 0, used: 0,
    unused: 0, remaining: 0, deactivated: 0, expired: 0, by_tier: {},
  };
  for (const r of rows.results || []) {
    const isExpired =
      r.expires_at != null && r.expires_at < now && r.status !== 'deactivated';
    const tier = (report.by_tier[r.tier] =
      report.by_tier[r.tier] || { issued: 0, used: 0, remaining: 0, deactivated: 0, expired: 0 });
    tier.issued += 1;
    report.issued += 1;
    if (r.status === 'used') {
      tier.used += 1;
      report.activated += 1;
      report.used += 1;
    } else if (r.status === 'deactivated') {
      tier.deactivated += 1;
      report.deactivated += 1;
    } else {
      report.unused += 1;
      if (!isExpired) {
        tier.remaining += 1;
        report.remaining += 1;
      }
    }
    if (isExpired) {
      tier.expired += 1;
      report.expired += 1;
    }
  }
  report.sold = report.issued;
  return report;
}

async function handleGenerate(env, request) {
  const gate = await requireRole(env, request, 'admin');
  if (gate.error) return gate.error;
  const { teacher_id, tier, count, expires_at } = await readJson(request);
  if (!TIERS[tier] || ![10, 20, 100].includes(Number(count))) {
    return json({ ok: false, error: 'tier must be SC5 or SC10 and count must be 10, 20 or 100' }, 400);
  }
  // Optional expiry: epoch milliseconds, or an ISO date string. Null
  // (the default) means the code never expires, as all codes did before.
  let expiresAt = null;
  if (expires_at !== undefined && expires_at !== null) {
    expiresAt = typeof expires_at === 'number' ? expires_at : Date.parse(expires_at);
    if (!Number.isFinite(expiresAt)) {
      return json({ ok: false, error: 'expires_at must be epoch milliseconds or an ISO date' }, 400);
    }
  }
  const teacher = await env.DB.prepare("SELECT id FROM users WHERE id = ? AND role = 'teacher'")
    .bind(teacher_id)
    .first();
  if (!teacher) return json({ ok: false, error: 'teacher not found' }, 404);
  const codes = [];
  let guard = 0;
  while (codes.length < Number(count) && guard < Number(count) * 20) {
    guard++;
    const code = makeCode(tier);
    const dup = await env.DB.prepare('SELECT code FROM licenses WHERE code = ?').bind(code).first();
    if (dup) continue;
    await env.DB.prepare(
      "INSERT INTO licenses (code, tier, max_profiles, teacher_id, status, expires_at, created_at) VALUES (?, ?, ?, ?, 'unused', ?, ?)",
    )
      .bind(code, tier, TIERS[tier].maxProfiles, teacher_id, expiresAt, Date.now())
      .run();
    codes.push(code);
  }
  if (codes.length < Number(count)) return json({ ok: false, error: 'could not generate enough unique codes, try again' }, 500);
  return json({ ok: true, tier, count: codes.length, expires_at: expiresAt, codes });
}

async function handleListLicenses(env, request, url) {
  const gate = await requireRole(env, request, null);
  if (gate.error) return gate.error;
  const { user } = gate;
  const status = url.searchParams.get('status');
  const tier = url.searchParams.get('tier');
  const teacherId = user.role === 'teacher' ? user.id : url.searchParams.get('teacher_id');
  let sql = 'SELECT code, tier, max_profiles, teacher_id, status, device_id, redeemed_at, expires_at, created_at FROM licenses';
  const args = [];
  const clauses = [];
  if (teacherId) {
    clauses.push('teacher_id = ?');
    args.push(teacherId);
  }
  if (tier === 'SC5' || tier === 'SC10') {
    clauses.push('tier = ?');
    args.push(tier);
  }
  if (status === 'used' || status === 'unused' || status === 'deactivated') {
    clauses.push('status = ?');
    args.push(status);
  }
  if (clauses.length) sql += ' WHERE ' + clauses.join(' AND ');
  sql += ' ORDER BY created_at DESC LIMIT 500';
  const rows = await env.DB.prepare(sql).bind(...args).all();
  return json({ ok: true, licenses: rows.results || [] });
}

async function handleTeachers(env, request) {
  const gate = await requireRole(env, request, 'admin');
  if (gate.error) return gate.error;
  const rows = await env.DB.prepare(
    "SELECT id, username, created_at FROM users WHERE role = 'teacher' ORDER BY created_at DESC",
  ).all();
  const teachers = [];
  for (const t of rows.results || []) {
    teachers.push({ ...t, report: await reportFor(env, t.id) });
  }
  return json({ ok: true, teachers });
}

// Admin-only: POST /api/v1/admin/licenses/:code/status
//   Body: { "action": "deactivate" | "reactivate" }
//   deactivate: an unused OR bound (used) code becomes 'deactivated'.
//     Its device_id/redeemed_at are kept for audit, but redeem is
//     rejected with code_deactivated until reactivated.
//   reactivate: a 'deactivated' code returns to 'unused' with its device
//     binding cleared (device_id and redeemed_at set to NULL), so it can
//     be activated fresh on any device. Reactivating a code that is not
//     deactivated is a clear 400 error ('not_deactivated'), not a silent
//     no-op. Deactivating an already-deactivated code is idempotent
//     (200, current status) — disabling twice is harmless.
//   HONEST LIMIT: this does NOT instantly lock an already-activated
//   device, because the app does not phone home continuously. It blocks
//   (re)activation and any future redeem of that code.
async function handleLicenseStatus(env, request, code) {
  const gate = await requireRole(env, request, 'admin');
  if (gate.error) return gate.error;
  const { action } = await readJson(request);
  const trimmed = decodeURIComponent(code).trim();
  const row = await env.DB.prepare('SELECT * FROM licenses WHERE code = ?').bind(trimmed).first();
  if (!row) return json({ ok: false, error: 'code_not_found', message: 'No such code.' }, 404);
  if (action === 'deactivate') {
    await env.DB.prepare("UPDATE licenses SET status = 'deactivated' WHERE code = ?").bind(trimmed).run();
    return json({ ok: true, code: trimmed, status: 'deactivated' });
  }
  if (action === 'reactivate') {
    if (row.status !== 'deactivated') {
      return json({ ok: false, error: 'not_deactivated', message: 'This code is not deactivated.' }, 400);
    }
    await env.DB.prepare(
      "UPDATE licenses SET status = 'unused', device_id = NULL, redeemed_at = NULL WHERE code = ?",
    )
      .bind(trimmed)
      .run();
    return json({ ok: true, code: trimmed, status: 'unused' });
  }
  return json({ ok: false, error: 'action must be deactivate or reactivate' }, 400);
}

// The endpoint the app's activate() TODO names: POST /api/v1/licenses/redeem.
// The app code specifies the path only — no request/response shape — so this
// contract is the dashboard's own, and app integration must use it as-is:
//   Request:  { "code": "SC5-...", "device_id": "<stable per-device id>" }
//   Success:  { ok: true, status: "activated" | "already_active_on_this_device",
//               tier: "SC5"|"SC10", max_profiles: 5|10 }
//   Rejected: 409 { ok: false, error: "already_in_use",
//               message: "This code is already in use on another device." }
//   Deactivated: 403 { ok: false, error: "code_deactivated", ... }
//   Expired: 403 { ok: false, error: "code_expired", ... }
//   Unknown/invalid code: 404 { ok: false, error: "invalid_code", ... }
// Re-pasting on the SAME bound device is idempotent (no second activation),
// unless the code has since been deactivated or expired — those reject.
// HONEST LIMIT: the app does not phone home continuously, so deactivating
// a code does NOT instantly lock an already-activated device offline; it
// blocks (re)activation and any future redeem of that code.
async function handleRedeem(env, request) {
  const { code, device_id } = await readJson(request);
  if (!code || !device_id) {
    return json({ ok: false, error: 'code and device_id are required' }, 400);
  }
  const tierKey = validateCode(code);
  if (!tierKey) return json({ ok: false, error: 'invalid_code', message: 'Invalid license code.' }, 404);
  const trimmed = String(code).trim();
  const row = await env.DB.prepare('SELECT * FROM licenses WHERE code = ?').bind(trimmed).first();
  if (!row) return json({ ok: false, error: 'invalid_code', message: 'This code was not issued by the dashboard.' }, 404);
  // Admin action wins over expiry: a deactivated code is rejected as
  // deactivated even if it also expired.
  if (row.status === 'deactivated') {
    return json(
      { ok: false, error: 'code_deactivated', message: 'This code has been deactivated. Please check with your teacher.' },
      403,
    );
  }
  // Expiry is checked before the idempotent same-device case: an
  // expired code is no longer valid even on the device it bound to.
  if (row.expires_at != null && row.expires_at < Date.now()) {
    return json(
      { ok: false, error: 'code_expired', message: 'This code has expired. Please check with your teacher.' },
      403,
    );
  }
  if (row.status === 'used' && row.device_id && row.device_id !== device_id) {
    return json(
      { ok: false, error: 'already_in_use', message: 'This code is already in use on another device.' },
      409,
    );
  }
  if (row.status === 'used' && row.device_id === device_id) {
    return json({ ok: true, status: 'already_active_on_this_device', tier: row.tier, max_profiles: row.max_profiles });
  }
  await env.DB.prepare("UPDATE licenses SET status = 'used', device_id = ?, redeemed_at = ? WHERE code = ?")
    .bind(String(device_id), Date.now(), trimmed)
    .run();
  return json({ ok: true, status: 'activated', tier: row.tier, max_profiles: row.max_profiles });
}

// ---- UI (single page; no build step; big buttons, phone-usable) ----
const UI = '<!doctype html><html lang="en"><head><meta charset="utf-8">'
  + '<meta name="viewport" content="width=device-width, initial-scale=1">'
  + '<title>Social Clone — License Dashboard</title>'
  + '<style>body{font-family:system-ui,sans-serif;margin:0 auto;max-width:720px;padding:16px;color:#111}'
  + 'h1{font-size:24px}h2{font-size:20px;margin-top:28px}input,select{font-size:18px;padding:12px;width:100%;box-sizing:border-box;margin:6px 0}'
  + 'button{font-size:18px;padding:14px 18px;margin:8px 6px 8px 0;cursor:pointer;background:#111;color:#fff;border:0;border-radius:8px}'
  + 'button.secondary{background:#e5e5e5;color:#111}table{width:100%;border-collapse:collapse;font-size:15px}'
  + 'td,th{border-bottom:1px solid #ddd;padding:8px;text-align:left;word-break:break-all}'
  + '.card{border:1px solid #ddd;border-radius:10px;padding:14px;margin:12px 0}.muted{color:#666;font-size:14px}</style></head>'
  + '<body><h1>Social Clone — License Dashboard</h1><p class="muted">Powered by SadSha</p>'
  + '<div id="setupCard" class="card" style="display:none"><h2>First setup</h2><p>No admin account exists yet. Create one now (choose a strong password — it is stored only as a hash).</p>'
  + '<input id="setupUser" placeholder="Admin username"><input id="setupPass" type="password" placeholder="Admin password (8+ characters)">'
  + '<button onclick="doSetup()">Create admin account</button><p id="setupMsg"></p></div>'
  + '<div id="loginCard" class="card"><h2>Log in</h2>'
  + '<input id="loginUser" placeholder="Username"><input id="loginPass" type="password" placeholder="Password">'
  + '<button onclick="doLogin()">Log in</button><p id="loginMsg"></p></div>'
  + '<div id="app" style="display:none"><p id="who"></p><button class="secondary" onclick="doLogout()">Log out</button>'
  + '<div id="adminPanel" style="display:none"><h2>Admin</h2><div class="card"><h3>Create teacher</h3>'
  + '<input id="tUser" placeholder="Teacher username"><input id="tPass" type="password" placeholder="Teacher password (8+ characters)">'
  + '<button onclick="createTeacher()">Create teacher</button><p id="tMsg"></p></div>'
  + '<div class="card"><h3>Generate codes</h3><select id="gTeacher"></select>'
  + '<select id="gTier"><option value="SC5">SC5 — 5 profiles (30 chars)</option><option value="SC10">SC10 — 10 profiles (40 chars)</option></select>'
  + '<select id="gCount"><option value="10">10 codes</option><option value="20">20 codes</option><option value="100">100 codes</option></select>'
  + '<button onclick="generate()">Generate</button><p id="gMsg"></p><div id="gCodes"></div></div>'
  + '<div class="card"><h3>Report</h3><div id="adminReport"></div></div></div>'
  + '<div id="teacherPanel" style="display:none"><h2>My codes</h2><div id="teacherReport"></div></div>'
  + '<h2>Codes</h2><label class="muted">Show: </label><select id="tierFilter" onchange="refresh()"><option value="">All tiers</option><option value="SC5">SC5 only — 5 profiles</option><option value="SC10">SC10 only — 10 profiles</option></select><div id="codes"></div></div>'
  + '<script>var token = localStorage.getItem("sc_token") || ""; var role = localStorage.getItem("sc_role") || "";'
  + 'function api(path, method, body){ var h = {"Content-Type":"application/json"}; if(token) h["Authorization"] = "Bearer " + token;'
  + ' return fetch(path, {method: method || "GET", headers: h, body: body ? JSON.stringify(body) : undefined}).then(function(r){ return r.json(); }); }'
  + 'function showMsg(id, o){ document.getElementById(id).textContent = o.ok ? "Done." : ("Error: " + (o.error || o.message || "failed")); }'
  + 'function renderCodes(list, isAdmin){ var html = "<table><tr><th>Code</th><th>Tier</th><th>Status</th><th>Device</th><th>Expires</th>";'
  + ' if(isAdmin) html += "<th>Action</th>"; html += "</tr>";'
  + ' list.forEach(function(c){ var cc = c.tier === "SC5" ? "#2563eb" : "#dc2626"; html += "<tr><td style=\'color:\' + cc + \';font-weight:bold\'>" + c.code + "</td><td>" + c.tier + "</td><td>" + c.status + "</td><td>" + (c.device_id || "-") + "</td><td>" + (c.expires_at ? new Date(c.expires_at).toLocaleDateString() : "never") + "</td>";'
  + ' if(isAdmin){ if(c.status === "deactivated") html += "<td><button onclick=\\"setLicenseStatus(\\"" + c.code + "\\", \\"reactivate\\")\\">Reactivate</button></td>";'
  + ' else html += "<td><button onclick=\\"setLicenseStatus(\\"" + c.code + "\\", \\"deactivate\\")\\">Deactivate</button></td>"; }'
  + ' html += "</tr>"; });'
  + ' document.getElementById("codes").innerHTML = html + "</table>"; }'
  + 'function renderReport(el, r){ document.getElementById(el).innerHTML = "Issued / sold: " + r.issued + " &nbsp; Activated: " + r.activated + " &nbsp; Remaining: " + r.remaining + " &nbsp; Deactivated: " + r.deactivated + " &nbsp; Expired: " + r.expired; }'
  + 'function setLicenseStatus(code, action){ api("/api/v1/admin/licenses/" + encodeURIComponent(code) + "/status", "POST", {action: action}).then(function(o){ if(!o.ok) alert("Error: " + (o.error || "failed")); refresh(); }); }'
  + 'function refresh(){ if(!token) return; document.getElementById("loginCard").style.display = "none"; document.getElementById("app").style.display = "block";'
  + ' document.getElementById("who").textContent = "Logged in as " + localStorage.getItem("sc_user") + " (" + role + ")";'
  + ' if(role === "admin"){ document.getElementById("adminPanel").style.display = "block";'
  + '  api("/api/v1/admin/teachers").then(function(o){ var s = document.getElementById("gTeacher"); s.innerHTML = "";'
  + '   (o.teachers || []).forEach(function(t){ var op = document.createElement("option"); op.value = t.id; op.textContent = t.username; s.appendChild(op); }); });'
  + '  api("/api/v1/admin/report").then(function(o){ renderReport("adminReport", o.report); }); }'
  + ' else { document.getElementById("teacherPanel").style.display = "block"; api("/api/v1/teacher/report").then(function(o){ renderReport("teacherReport", o.report); }); }'
  + ' var tf = document.getElementById("tierFilter") ? document.getElementById("tierFilter").value : ""; api("/api/v1/licenses" + (tf ? "?tier=" + tf : "")).then(function(o){ renderCodes(o.licenses || [], role === "admin"); }); }'
  + 'function doSetup(){ var u = document.getElementById("setupUser").value; var p = document.getElementById("setupPass").value;'
  + ' api("/api/v1/setup", "POST", {username: u, password: p}).then(function(o){ showMsg("setupMsg", o); if(o.ok) init(); }); }'
  + 'function doLogin(){ var u = document.getElementById("loginUser").value; var p = document.getElementById("loginPass").value;'
  + ' api("/api/v1/auth/login", "POST", {username: u, password: p}).then(function(o){ if(o.ok){ token = o.token; role = o.role;'
  + '  localStorage.setItem("sc_token", token); localStorage.setItem("sc_role", role); localStorage.setItem("sc_user", o.username); refresh(); }'
  + '  else showMsg("loginMsg", o); }); }'
  + 'function doLogout(){ api("/api/v1/auth/logout", "POST", {}).then(function(){ token = ""; role = ""; localStorage.clear(); location.reload(); }); }'
  + 'function createTeacher(){ var u = document.getElementById("tUser").value; var p = document.getElementById("tPass").value;'
  + ' api("/api/v1/admin/teachers", "POST", {username: u, password: p}).then(function(o){ showMsg("tMsg", o); if(o.ok) refresh(); }); }'
  + 'function generate(){ var t = document.getElementById("gTeacher").value; var tier = document.getElementById("gTier").value; var n = document.getElementById("gCount").value;'
  + ' api("/api/v1/admin/licenses/generate", "POST", {teacher_id: t, tier: tier, count: Number(n)}).then(function(o){'
  + '  if(o.ok){ document.getElementById("gMsg").textContent = "Generated " + o.count + " " + o.tier + " codes.";'
  + '   var gc = tier === "SC5" ? "#2563eb" : "#dc2626"; document.getElementById("gCodes").innerHTML = "<p style=\'color:\' + gc + \';font-weight:bold\'>" + o.codes.join("<br>") + "</p>"; refresh(); } else showMsg("gMsg", o); }); }'
  + 'function init(){ api("/api/v1/setup/status").then(function(o){ if(o.needs_setup) document.getElementById("setupCard").style.display = "block"; }); if(token) refresh(); }'
  + 'init();</script></body></html>';

// ---- router ----
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    try {
      if (path === '/' && method === 'GET') {
        return new Response(UI, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
      }
      if (path === '/api/v1/setup/status' && method === 'GET') {
        const admin = await env.DB.prepare("SELECT id FROM users WHERE role = 'admin' LIMIT 1").first();
        return json({ ok: true, needs_setup: !admin });
      }
      if (path === '/api/v1/setup' && method === 'POST') return handleSetup(env, request);
      if (path === '/api/v1/auth/login' && method === 'POST') return handleLogin(env, request);
      if (path === '/api/v1/auth/logout' && method === 'POST') return handleLogout(env, request);
      if (path === '/api/v1/admin/teachers' && method === 'POST') return handleCreateTeacher(env, request);
      if (path === '/api/v1/admin/teachers' && method === 'GET') return handleTeachers(env, request);
      if (path === '/api/v1/admin/licenses/generate' && method === 'POST') return handleGenerate(env, request);
      if (path === '/api/v1/admin/report' && method === 'GET') {
        const gate = await requireRole(env, request, 'admin');
        if (gate.error) return gate.error;
        return json({ ok: true, report: await reportFor(env, null) });
      }
      if (path === '/api/v1/teacher/report' && method === 'GET') {
        const gate = await requireRole(env, request, 'teacher');
        if (gate.error) return gate.error;
        return json({ ok: true, report: await reportFor(env, gate.user.id) });
      }
      if (path === '/api/v1/licenses' && method === 'GET') return handleListLicenses(env, request, url);
      if (path.startsWith('/api/v1/admin/licenses/') && path.endsWith('/status') && method === 'POST') {
        const code = path.slice('/api/v1/admin/licenses/'.length, -'/status'.length);
        return handleLicenseStatus(env, request, code);
      }
      if (path === '/api/v1/licenses/redeem' && method === 'POST') return handleRedeem(env, request);
      return json({ ok: false, error: 'not found' }, 404);
    } catch (e) {
      return json({ ok: false, error: 'server error: ' + (e && e.message ? e.message : 'unknown') }, 500);
    }
  },
};
