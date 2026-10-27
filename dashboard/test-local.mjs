// Local verification for the Social Clone dashboard Worker — NO Cloudflare.
// Runs the real Worker code in Node 24 against node:sqlite as a mock D1.
// Test passwords are generated at runtime and never printed or stored.
// Run: node test-local.mjs   (exit 0 = all checks passed)
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { makeCode, validateCode } from './src/index.js';

const db = new DatabaseSync(':memory:');
db.exec(readFileSync(new URL('./schema.sql', import.meta.url), 'utf8'));

class Stmt {
  constructor(sql) {
    this.stmt = db.prepare(sql);
    this.args = [];
  }
  bind(...args) {
    this.args = args;
    return this;
  }
  all() {
    return { results: this.stmt.all(...this.args) };
  }
  first() {
    return this.stmt.get(...this.args) ?? null;
  }
  run() {
    const info = this.stmt.run(...this.args);
    return { success: true, meta: { changes: info.changes } };
  }
}
const env = { DB: { prepare: (sql) => new Stmt(sql) } };

let pass = 0;
function check(name, cond, extra = '') {
  if (!cond) {
    console.log('FAIL: ' + name + (extra ? ' — ' + extra : ''));
    process.exitCode = 1;
  } else {
    pass++;
    console.log('PASS: ' + name);
  }
}
async function call(path, method, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  const req = new Request('http://dashboard.local' + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const res = await worker.fetch(req, env);
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { _raw: text };
  }
  return { status: res.status, data, text };
}
// Independent re-implementation of the Dart checksum (spec, not worker code).
function independentChecksum(body) {
  let sum = 0;
  for (let i = 0; i < body.length; i++) sum += body.charCodeAt(i) * (i + 1);
  let value = (sum % 1296) * 1296;
  const alpha = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const chars = [];
  for (let i = 0; i < 4; i++) {
    chars.push(alpha[value % 36]);
    value = Math.floor(value / 36);
  }
  return chars.reverse().join('');
}
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*';
function randomPassword() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join('') + '9!';
}

const adminPass = randomPassword();
const teacherPass = randomPassword();
const teacher2Pass = randomPassword();

let r = await call('/', 'GET');
check('UI serves HTML', r.status === 200 && r.text.includes('License Dashboard'));
r = await call('/api/v1/setup/status', 'GET');
check('setup needed at start', r.data.needs_setup === true);
r = await call('/api/v1/setup', 'POST', { username: 'testadmin', password: adminPass });
check('admin setup succeeds', r.status === 200 && r.data.ok === true);
r = await call('/api/v1/setup', 'POST', { username: 'second', password: adminPass });
check('second setup rejected', r.status === 403);
r = await call('/api/v1/auth/login', 'POST', { username: 'testadmin', password: 'wrong-password-1' });
check('wrong admin password rejected', r.status === 401);
r = await call('/api/v1/auth/login', 'POST', { username: 'testadmin', password: adminPass });
check('admin login succeeds', r.status === 200 && r.data.role === 'admin' && !!r.data.token);
const adminToken = r.data.token;
r = await call('/api/v1/admin/teachers', 'POST', { username: 'testteacher', password: teacherPass }, adminToken);
check('teacher created', r.status === 200 && !!r.data.id);
const teacherId = r.data.id;
r = await call('/api/v1/admin/teachers', 'POST', { username: 'testteacher', password: teacherPass }, adminToken);
check('duplicate teacher rejected', r.status === 409);
r = await call('/api/v1/admin/licenses/generate', 'POST', { teacher_id: teacherId, tier: 'SC5', count: 5 }, adminToken);
check('invalid batch size rejected', r.status === 400);
r = await call('/api/v1/admin/licenses/generate', 'POST', { teacher_id: teacherId, tier: 'SC5', count: 10 }, adminToken);
check('SC5 batch of 10 generated', r.status === 200 && r.data.codes.length === 10);
const codes = r.data.codes;
let formatOk = true;
for (const c of codes) {
  if (c.length !== 30 || !c.startsWith('SC5-') || validateCode(c) !== 'SC5') formatOk = false;
  if (c.slice(-4) !== independentChecksum(c.slice(0, 26))) formatOk = false;
  const randomPart = c.slice(4, 26);
  for (const ch of randomPart) if (!ALPHABET.includes(ch)) formatOk = false;
}
check('SC5 codes match Dart format + independent checksum', formatOk);
const codeA = codes[0];
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeA, device_id: 'device-A' });
check('redeem on device A activates', r.status === 200 && r.data.status === 'activated' && r.data.max_profiles === 5);
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeA, device_id: 'device-B' });
check(
  'redeem on device B rejected with already-in-use message',
  r.status === 409 && r.data.error === 'already_in_use' && r.data.message === 'This code is already in use on another device.',
);
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeA, device_id: 'device-A' });
check('re-redeem on device A is idempotent', r.status === 200 && r.data.status === 'already_active_on_this_device');
r = await call('/api/v1/licenses/redeem', 'POST', { code: makeCode('SC5'), device_id: 'device-A' });
check('unissued well-formed code rejected', r.status === 404 && r.data.error === 'invalid_code');
r = await call('/api/v1/licenses/redeem', 'POST', { code: 'SC5-NOTAREALCODE', device_id: 'device-A' });
check('malformed code rejected', r.status === 404);
r = await call('/api/v1/auth/login', 'POST', { username: 'testteacher', password: teacherPass });
check('teacher login succeeds', r.status === 200 && r.data.role === 'teacher');
const teacherToken = r.data.token;
r = await call('/api/v1/licenses', 'GET', null, teacherToken);
check(
  'teacher sees only own codes, redeemed one marked used on device A',
  r.data.licenses.length === 10 &&
    r.data.licenses.find((c) => c.code === codeA).status === 'used' &&
    r.data.licenses.find((c) => c.code === codeA).device_id === 'device-A',
);
r = await call('/api/v1/teacher/report', 'GET', null, teacherToken);
check('teacher report 10 issued / 1 used / 9 remaining', r.data.report.issued === 10 && r.data.report.used === 1 && r.data.report.remaining === 9);
r = await call('/api/v1/admin/teachers', 'POST', { username: 'testteacher2', password: teacher2Pass }, adminToken);
const teacher2Id = r.data.id;
r = await call('/api/v1/admin/licenses/generate', 'POST', { teacher_id: teacher2Id, tier: 'SC10', count: 20 }, adminToken);
check('SC10 batch of 20 generated', r.status === 200 && r.data.codes.length === 20);
let sc10Ok = true;
for (const c of r.data.codes) {
  if (c.length !== 40 || !c.startsWith('SC10-') || validateCode(c) !== 'SC10') sc10Ok = false;
  if (c.slice(-4) !== independentChecksum(c.slice(0, 36))) sc10Ok = false;
}
check('SC10 codes match Dart format + independent checksum', sc10Ok);
r = await call('/api/v1/licenses/redeem', 'POST', { code: r.data.codes[0], device_id: 'device-C' });
check('SC10 redeem activates with 10 profiles', r.status === 200 && r.data.max_profiles === 10);
r = await call('/api/v1/licenses', 'GET', null, teacherToken);
check('teacher 1 still sees only own 10 codes after teacher 2 batch', r.data.licenses.length === 10);
r = await call('/api/v1/admin/report', 'GET', null, adminToken);
check('admin report 30 issued / 2 used / 28 remaining', r.data.report.issued === 30 && r.data.report.used === 2 && r.data.report.remaining === 28);
r = await call('/api/v1/licenses', 'GET', null, null);
check('licenses list requires login', r.status === 401);

// ---- Stats, deactivate/reactivate, expiry (added 2026-10-26) ----
// State at this point: teacher1 10 SC5 (codeA used on device-A),
// teacher2 20 SC10 (one used on device-C). Totals: 30 / 2 used.
r = await call('/api/v1/admin/report', 'GET', null, adminToken);
check(
  'admin report new fields: sold = issued, activated = used, no deactivated/expired yet',
  r.data.report.issued === 30 && r.data.report.sold === 30 && r.data.report.activated === 2 &&
    r.data.report.used === 2 && r.data.report.unused === 28 && r.data.report.remaining === 28 &&
    r.data.report.deactivated === 0 && r.data.report.expired === 0,
);
const codeB = codes[1];
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codeB) + '/status', 'POST', { action: 'deactivate' }, adminToken);
check('deactivate unused code succeeds', r.status === 200 && r.data.status === 'deactivated');
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeB, device_id: 'device-A' });
check('redeem of deactivated code rejected with code_deactivated', r.status === 403 && r.data.error === 'code_deactivated');
r = await call('/api/v1/admin/report', 'GET', null, adminToken);
check('admin report after deactivate: deactivated 1, remaining 27', r.data.report.deactivated === 1 && r.data.report.remaining === 27);
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codeB) + '/status', 'POST', { action: 'reactivate' }, adminToken);
check('reactivate returns code to unused', r.status === 200 && r.data.status === 'unused');
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeB, device_id: 'device-X' });
check('reactivated code activates fresh', r.status === 200 && r.data.status === 'activated');
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codeA) + '/status', 'POST', { action: 'deactivate' }, adminToken);
check('deactivate bound code succeeds', r.status === 200 && r.data.status === 'deactivated');
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeA, device_id: 'device-A' });
check('redeem of deactivated bound code rejected even on its own device', r.status === 403 && r.data.error === 'code_deactivated');
r = await call('/api/v1/licenses?status=deactivated', 'GET', null, adminToken);
check(
  'deactivated filter lists the bound code with its old device kept for audit',
  r.data.licenses.some((c) => c.code === codeA && c.device_id === 'device-A'),
);
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codeA) + '/status', 'POST', { action: 'reactivate' }, adminToken);
check('reactivate bound code succeeds', r.status === 200 && r.data.status === 'unused');
r = await call('/api/v1/licenses', 'GET', null, teacherToken);
check(
  'reactivated code shows unused with binding cleared',
  r.data.licenses.find((c) => c.code === codeA).status === 'unused' &&
    r.data.licenses.find((c) => c.code === codeA).device_id === null,
);
r = await call('/api/v1/licenses/redeem', 'POST', { code: codeA, device_id: 'device-B' });
check('reactivated code activates on a different device (binding was cleared)', r.status === 200 && r.data.status === 'activated');
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codeA) + '/status', 'POST', { action: 'reactivate' }, adminToken);
check('reactivating a non-deactivated code is a clear 400', r.status === 400 && r.data.error === 'not_deactivated');
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(makeCode('SC5')) + '/status', 'POST', { action: 'deactivate' }, adminToken);
check('deactivate unknown code is 404', r.status === 404 && r.data.error === 'code_not_found');
r = await call('/api/v1/admin/licenses/' + encodeURIComponent(codes[2]) + '/status', 'POST', { action: 'deactivate' }, teacherToken);
check('teacher cannot deactivate (admin only)', r.status === 403);
r = await call('/api/v1/admin/licenses/generate', 'POST', { teacher_id: teacher2Id, tier: 'SC5', count: 10, expires_at: Date.now() - 1000 }, adminToken);
check('batch with past expiry generated', r.status === 200 && r.data.codes.length === 10);
const expiredCode = r.data.codes[0];
r = await call('/api/v1/licenses/redeem', 'POST', { code: expiredCode, device_id: 'device-A' });
check('redeem of expired code rejected with code_expired', r.status === 403 && r.data.error === 'code_expired');
r = await call('/api/v1/admin/licenses/generate', 'POST', { teacher_id: teacher2Id, tier: 'SC5', count: 10, expires_at: Date.now() + 24 * 60 * 60 * 1000 }, adminToken);
check('batch with future expiry generated', r.status === 200 && r.data.codes.length === 10);
r = await call('/api/v1/licenses/redeem', 'POST', { code: r.data.codes[0], device_id: 'device-D' });
check('not-yet-expired code activates', r.status === 200 && r.data.status === 'activated');
r = await call('/api/v1/admin/report', 'GET', null, adminToken);
check(
  'final admin report: 50 issued/sold, 4 activated, 46 unused, 36 remaining, 0 deactivated, 10 expired',
  r.data.report.issued === 50 && r.data.report.sold === 50 && r.data.report.activated === 4 &&
    r.data.report.unused === 46 && r.data.report.remaining === 36 &&
    r.data.report.deactivated === 0 && r.data.report.expired === 10,
);
r = await call('/api/v1/auth/login', 'POST', { username: 'testteacher2', password: teacher2Pass });
const teacher2Token = r.data.token;
r = await call('/api/v1/teacher/report', 'GET', null, teacher2Token);
check(
  'teacher2 report: 40 issued, 2 activated, 38 unused, 28 remaining, 10 expired',
  r.data.report.issued === 40 && r.data.report.activated === 2 && r.data.report.unused === 38 &&
    r.data.report.remaining === 28 && r.data.report.expired === 10 && r.data.report.deactivated === 0,
);

// ---- Wallet, password change, admin view, active/expired (added 2026-10-27) ----
r = await call('/api/v1/admin/teachers/credit', 'POST', { teacher_id: teacherId, amount_pkr: 30000 }, adminToken);
check('admin credits teacher1 Rs 30,000', r.status === 200 && r.data.balance_pkr === 30000);
r = await call('/api/v1/teacher/wallet', 'GET', null, teacherToken);
check('teacher wallet shows Rs 30,000 and 1 credit transaction', r.data.balance_pkr === 30000 && r.data.transactions.length === 1 && r.data.transactions[0].kind === 'credit');
r = await call('/api/v1/teacher/licenses/generate', 'POST', { tier: 'SC5' }, teacherToken);
check('teacher generates SC5, balance drops to Rs 28,600', r.status === 200 && r.data.code.length === 30 && r.data.price_pkr === 1400 && r.data.balance_pkr === 28600);
const walletCode5 = r.data.code;
r = await call('/api/v1/teacher/licenses/generate', 'POST', { tier: 'SC10' }, teacherToken);
check('teacher generates SC10, balance drops to Rs 26,920', r.status === 200 && r.data.code.length === 40 && r.data.price_pkr === 1680 && r.data.balance_pkr === 26920);
const walletCode10 = r.data.code;
r = await call('/api/v1/teacher/licenses/generate', 'POST', { tier: 'SC5' }, teacher2Token);
check('teacher2 with Rs 0 balance is rejected insufficient_balance, no code made', r.status === 400 && r.data.error === 'insufficient_balance');
r = await call('/api/v1/admin/teachers/credit', 'POST', { teacher_id: teacher2Id, amount_pkr: 1400 }, adminToken);
check('admin credits teacher2 Rs 1,400', r.status === 200 && r.data.balance_pkr === 1400);
r = await call('/api/v1/teacher/licenses/generate', 'POST', { tier: 'SC5' }, teacher2Token);
check('teacher2 generates SC5 and balance hits Rs 0', r.status === 200 && r.data.balance_pkr === 0);
r = await call('/api/v1/admin/teachers/credit', 'POST', { teacher_id: teacherId, amount_pkr: 1000 }, teacherToken);
check('teacher cannot credit (admin only)', r.status === 403);
r = await call('/api/v1/teacher/licenses/generate', 'POST', { tier: 'SC5' }, adminToken);
check('admin cannot use teacher generate endpoint', r.status === 403);
r = await call('/api/v1/admin/teacher-view?teacher_id=' + teacherId, 'GET', null, teacherToken);
check('teacher cannot view admin teacher-view', r.status === 403);
r = await call('/api/v1/admin/teacher-view?teacher_id=' + teacherId, 'GET', null, adminToken);
check(
  'admin teacher-view shows balance, generated codes and ledger',
  r.status === 200 && r.data.teacher.balance_pkr === 26920 &&
    r.data.licenses.some((c) => c.code === walletCode5) &&
    r.data.licenses.some((c) => c.code === walletCode10) &&
    r.data.transactions.length === 3,
);
r = await call('/api/v1/admin/users/active-expired', 'GET', null, adminToken);
check(
  'active/expired section: 4 active, 10 expired, every entry tagged with a teacher',
  r.status === 200 && r.data.active.length === 4 && r.data.expired.length === 10 &&
    r.data.active.every((u) => !!u.teacher) && r.data.expired.every((u) => !!u.teacher),
);
r = await call('/api/v1/admin/users/active-expired', 'GET', null, teacherToken);
check('teacher cannot view active/expired section', r.status === 403);
const teacherNewPass = randomPassword();
r = await call('/api/v1/auth/change-password', 'POST', { current_password: 'wrong-password-1', new_password: teacherNewPass }, teacherToken);
check('password change with wrong current password rejected', r.status === 401);
r = await call('/api/v1/auth/change-password', 'POST', { current_password: teacherPass, new_password: teacherNewPass }, teacherToken);
check('teacher password change succeeds', r.status === 200 && r.data.ok === true);
r = await call('/api/v1/auth/login', 'POST', { username: 'testteacher', password: teacherPass });
check('old teacher password no longer works', r.status === 401);
r = await call('/api/v1/auth/login', 'POST', { username: 'testteacher', password: teacherNewPass });
check('new teacher password works', r.status === 200 && r.data.role === 'teacher');
const adminNewPass = randomPassword();
r = await call('/api/v1/auth/change-password', 'POST', { current_password: adminPass, new_password: adminNewPass }, adminToken);
check('admin password change succeeds', r.status === 200 && r.data.ok === true);
r = await call('/api/v1/auth/login', 'POST', { username: 'testadmin', password: adminPass });
check('old admin password no longer works', r.status === 401);
r = await call('/api/v1/auth/login', 'POST', { username: 'testadmin', password: adminNewPass });
check('new admin password works', r.status === 200 && r.data.role === 'admin');

console.log('\n' + pass + ' checks passed, exit ' + (process.exitCode || 0));
