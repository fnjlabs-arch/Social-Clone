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

console.log('\n' + pass + ' checks passed, exit ' + (process.exitCode || 0));
