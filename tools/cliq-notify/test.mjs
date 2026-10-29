// Offline tests for relay.mjs. Multica reads are REAL (read-only); Cliq is a local stand-in server. Nothing is sent to Cliq.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mcn-'));
process.env.MCN_CONF_DIR = path.join(tmp, 'conf');
process.env.MCN_STATE_DIR = path.join(tmp, 'state');
const { createRelay, loadConfig, mask, STATE_DIR } = await import('./relay.mjs');

const SECRET_KEY = 'zapikey=SUPERSECRETKEY123456';
let mode = 'ok', calls = [];
const server = http.createServer((req, res) => {
  let b = ''; req.on('data', (d) => (b += d)); req.on('end', () => {
    calls.push({ url: req.url, method: req.method, ct: req.headers['content-type'], body: b, t: Date.now() });
    const n = calls.length;
    if (mode === 'flaky' && n % 3 !== 0) { res.statusCode = 500; return res.end('boom'); }
    if (mode === 'unauthorized') { res.statusCode = 401; return res.end(`bad key ${SECRET_KEY}`); }
    res.statusCode = 200; res.end('{"ok":true}');
  });
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const endpoint = `http://127.0.0.1:${port}/hook?${SECRET_KEY}`;

const { cfg, token } = loadConfig();
cfg.min_send_gap_ms = 50;
const secrets = { CLIQ_ENDPOINT: endpoint };
const logs = [];
const origLog = console.log; console.log = (...a) => { logs.push(a.join(' ')); };
const out = (...a) => origLog(...a);

let pass = 0;
const t = async (name, fn) => { try { await fn(); pass++; out('PASS ', name); } catch (e) { out('FAIL ', name, '->', e.message); process.exitCode = 1; } };

const mk = (over = {}) => createRelay({ cfg, secrets, token, ...over });
let relay = mk();
const me = await relay.getMe();
const inbox = await relay.api('/api/inbox');
const real = inbox.filter((i) => i.type === 'mentioned' && i.recipient_id === me.id);
const realComment = inbox.find((i) => i.type === 'new_comment');
assert(real.length > 0, 'need at least one real mention');
const fake = (n, over = {}) => ({ ...real[0], id: `test-${Date.now()}-${n}`, created_at: new Date().toISOString(), archived: false, ...over });

await t('first run only baselines: existing mentions are marked seen, nothing is sent', async () => {
  calls = [];
  await relay.catchUp();
  assert.equal(calls.length, 0, 'sent during baseline');
  assert.equal(relay.state.baseline_done, true);
  assert(relay.sentSet.size >= real.length);
});

await t('a live mention frame sends exactly one Cliq message with the right shape', async () => {
  calls = []; const item = fake(1);
  await relay.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(calls.length, 1);
  const c = calls[0];
  assert.equal(c.method, 'POST'); assert.match(c.ct, /application\/json/);
  const body = JSON.parse(c.body);
  assert.equal(Object.keys(body).join(','), 'text');
  assert.match(body.text, /mentioned you on \*CIRD-\d+\*/);
  assert.doesNotMatch(body.text, /https?:\/\//);   // no web link (multica.ai is not reachable from the user's network)
  assert.match(body.text, /\nIssue: CIRD-\d+ {3}\(search this in the Multica app\)$/);
  assert(!body.text.includes('mention://'), 'raw mention link leaked');
  assert(body.text.length < 1200, 'message too long: ' + body.text.length);
});

await t('the same event twice sends once (duplicate frame)', async () => {
  calls = []; const item = fake(2);
  await relay.handleFrame({ type: 'inbox:new', payload: { item } });
  await relay.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(calls.length, 1);
});

await t('other types and other recipients are ignored', async () => {
  calls = [];
  await relay.handleFrame({ type: 'inbox:new', payload: { item: { ...realComment, id: 'x1' } } });
  await relay.handleFrame({ type: 'inbox:new', payload: { item: fake(3, { recipient_id: '00000000-0000-0000-0000-000000000000' }) } });
  await relay.handleFrame({ type: 'inbox:new', payload: { item: fake(4, { archived: true }) } });
  await relay.handleFrame({ type: 'task:message', payload: {} });
  await relay.handleFrame({ type: 'inbox:new' });
  await relay.handleFrame(null);
  assert.equal(calls.length, 0);
});

await t('a flaky Cliq (500, 500, 200) is retried and the mention is sent once and recorded', async () => {
  mode = 'flaky'; calls = []; const item = fake(5);
  const r = await relay.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(r, 'sent'); assert.equal(calls.length, 3); assert(relay.sentSet.has(item.id));
  mode = 'ok';
});

await t('a rejected key (401) is not retried, not recorded, and its error text never shows the key', async () => {
  mode = 'unauthorized'; calls = []; logs.length = 0; const item = fake(6);
  const r = await relay.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(r, 'failed'); assert.equal(calls.length, 1, 'retried a fatal error'); assert(!relay.sentSet.has(item.id));
  assert(!logs.join('\n').includes('SUPERSECRETKEY'), 'secret in log');
  assert.match(logs.join('\n'), /FAILED to deliver/);
  mode = 'ok';
});

await t('a failed mention is delivered by the next catch-up once Cliq works (nothing lost)', async () => {
  // simulate: an inbox item that is real, was never recorded as sent
  const target = real[real.length - 1];
  relay.sentSet.delete(target.id); target.__orig = target.created_at;
  const fresh = { ...target, created_at: new Date().toISOString() };
  calls = [];
  const orig = relay.api; // catch-up reads the real inbox; use a relay with a patched fetch for the list
  const patched = mk({ fetchImpl: async (u, o) => {
    const r = await fetch(u, o);
    if (String(u).endsWith('/api/inbox')) { const j = await r.json(); j.forEach((i) => { if (i.id === target.id) i.created_at = fresh.created_at; }); return new Response(JSON.stringify(j), { status: 200 }); }
    return r;
  } });
  patched.state.baseline_done = true;
  patched.sentSet.clear(); inbox.filter((i) => i.type === 'mentioned' && i.id !== target.id).forEach((i) => patched.sentSet.add(i.id));
  await patched.catchUp();
  assert.equal(calls.length, 1, 'expected exactly the one pending mention');
});

await t('after a restart the saved state prevents re-sending', async () => {
  const again = mk();
  calls = [];
  await again.catchUp();
  assert.equal(calls.length, 0, 'sent again after restart: ' + calls.length);
  assert(fs.statSync(path.join(STATE_DIR, 'state.json')).mode & 0o600);
  assert.equal(fs.statSync(path.join(STATE_DIR, 'state.json')).mode & 0o077, 0, 'state file readable by others');
});

await t('a burst of 5 mentions arrives in order, spaced by the send gap', async () => {
  const slow = mk(); slow.state.baseline_done = true; calls = [];
  const items = [1, 2, 3, 4, 5].map((n) => fake(`b${n}`));
  await Promise.all(items.map((i) => slow.handleFrame({ type: 'inbox:new', payload: { item: i } })));
  assert.equal(calls.length, 5);
  for (let i = 1; i < calls.length; i++) assert(calls[i].t - calls[i - 1].t >= 40, 'no spacing');
});

await t('masking removes tokens, keys and bearer values from text', () => {
  const s = mask('token=abc123 zapikey=XYZ789 Authorization: Bearer mul_abcdefghijklmnopqrstuvwxyz0123 refresh_token: 1000.aa.bb');
  assert(!/abc123|XYZ789|mul_abcdefghij|1000\.aa/.test(s), s);
});

await t('a comment that contains a secret is masked in the Cliq message', async () => {
  calls = [];
  const r = mk(); r.state.baseline_done = true;
  const item = fake('s1');
  const orig = r.buildMessage;
  // feed a comment through the real snippet path by faking the comment fetch
  const r2 = mk({ fetchImpl: async (u, o) => {
    if (String(u).includes('/comments')) return new Response(JSON.stringify([{ id: item.details.comment_id, content: 'please use token=SECRETVALUE99 and [@balaji.rk](mention://member/567d94d2-518b-4e10-9d36-b613d0dbb22b)', author_type: 'agent' }]), { status: 200 });
    return fetch(u, o);
  } });
  r2.state.baseline_done = true;
  await r2.handleFrame({ type: 'inbox:new', payload: { item } });
  const text = JSON.parse(calls[0].body).text;
  assert(!text.includes('SECRETVALUE99'), text); assert(text.includes('@balaji.rk') && !text.includes('mention://'));
});

await t('dry-run prints and never posts or records', async () => {
  const d = mk({ dryRun: true }); calls = [];
  const item = fake('d1'); logs.length = 0;
  const r = await d.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(r, 'dry-run'); assert.equal(calls.length, 0); assert(!d.sentSet.has(item.id));
});

await t('no Cliq settings: reports clearly instead of crashing, and keeps the mention for later', async () => {
  const n = mk({ secrets: {} }); n.state.baseline_done = true; const item = fake('n1'); logs.length = 0;
  const r = await n.handleFrame({ type: 'inbox:new', payload: { item } });
  assert.equal(r, 'failed'); assert(!n.sentSet.has(item.id)); assert.match(logs.join('\n'), /not configured/);
});


await t('a rotated Multica token is picked up after a 401 and the request succeeds', async () => {
  let good = token; let stale = 'mul_stale00000000000000000000000000000000';
  const r = createRelay({ cfg, secrets, token: stale, getToken: () => good });
  const m = await r.getMe();           // first call uses the stale token (401), re-reads, retries
  assert(m.id); assert.equal(r.token(), good);
});

await t('snippet_chars=0 sends only the headline and the identifier line (no comment text)', async () => {
  calls = [];
  const c2 = { ...cfg, snippet_chars: 0 };
  const r = createRelay({ cfg: c2, secrets, token }); r.state.baseline_done = true;
  await r.handleFrame({ type: 'inbox:new', payload: { item: fake('nosnip') } });
  const text = JSON.parse(calls[0].body).text;
  assert.equal(text.split('\n').filter(Boolean).length, 2, text);   // headline, identifier line
  assert.match(text, /\nIssue: CIRD-\d+ {3}\(search this in the Multica app\)$/);
});

const { exchangeCode } = await import('./relay.mjs');
await t('exchange-code writes the refresh token to a mode-600 file, never prints it, and replaces an old one', async () => {
  const f = path.join(tmp, 'secrets-x.env');
  fs.writeFileSync(f, '# c\nCLIQ_CLIENT_ID=cid\nCLIQ_CLIENT_SECRET=csec\nCLIQ_REFRESH_TOKEN=old\n', { mode: 0o644 });
  const seen = [];
  const fakeZoho = async (u, o) => { seen.push(String(u)); return new Response(JSON.stringify({ access_token: 'AT', refresh_token: '1000.newrefresh.token', scope: 'ZohoCliq.Webhooks.CREATE' }), { status: 200 }); };
  const out = await exchangeCode({ secrets: { CLIQ_CLIENT_ID: 'cid', CLIQ_CLIENT_SECRET: 'csec', CLIQ_ACCOUNTS: 'https://accounts.zoho.in' }, code: '1000.abcdef0123.abcdef0123', fetchImpl: fakeZoho, secretsFile: f });
  const text = fs.readFileSync(f, 'utf8');
  assert.match(text, /CLIQ_REFRESH_TOKEN=1000\.newrefresh\.token/); assert(!text.includes('=old'));
  assert.equal(text.match(/CLIQ_REFRESH_TOKEN/g).length, 1);
  assert.equal(fs.statSync(f).mode & 0o777, 0o600);
  assert(seen[0].startsWith('https://accounts.zoho.in/oauth/v2/token?') && seen[0].includes('grant_type=authorization_code'));
  assert(!JSON.stringify(out).includes('newrefresh'));
});
await t('exchange-code explains a used/expired code and a bad code format', async () => {
  const bad = async () => new Response(JSON.stringify({ error: 'invalid_code' }), { status: 400 });
  await assert.rejects(exchangeCode({ secrets: { CLIQ_CLIENT_ID: 'a', CLIQ_CLIENT_SECRET: 'b' }, code: '1000.aa.bb', fetchImpl: bad, secretsFile: path.join(tmp, 's2.env') }), /already used or has expired/);
  await assert.rejects(exchangeCode({ secrets: { CLIQ_CLIENT_ID: 'a', CLIQ_CLIENT_SECRET: 'b' }, code: 'hello', fetchImpl: bad, secretsFile: path.join(tmp, 's3.env') }), /does not look like a Zoho code/);
  await assert.rejects(exchangeCode({ secrets: {}, code: '1000.aa.bb', fetchImpl: bad, secretsFile: path.join(tmp, 's4.env') }), /CLIQ_CLIENT_ID is missing/);
});
await t('--check names the missing OAuth value and a Cliq 401 shows the error code, with a hint, without secrets', async () => {
  const r = createRelay({ cfg, secrets: { CLIQ_BOT: 'b', CLIQ_CLIENT_ID: 'cid', CLIQ_CLIENT_SECRET: 'sec' }, token });
  const c = await r.check();
  assert.match(c.problems.join(' '), /Missing in secrets\.env: CLIQ_REFRESH_TOKEN/); assert.match(c.problems.join(' '), /--exchange-code/);
  const f401 = async (u) => String(u).includes('oauth') ? new Response(JSON.stringify({ access_token: 'AT' }), { status: 200 }) : new Response(JSON.stringify({ code: 'oauthtoken_invalid', message: 'Invalid OAuth token passed.' }), { status: 401 });
  const r2 = createRelay({ cfg, secrets: { CLIQ_BOT: 'b', CLIQ_CLIENT_ID: 'cid', CLIQ_CLIENT_SECRET: 'sec', CLIQ_REFRESH_TOKEN: 'rt' }, token, fetchImpl: async (u, o) => (String(u).startsWith('https://api.multica.ai') ? fetch(u, o) : f401(u)) });
  await assert.rejects(r2.postCliq('x'), /HTTP 401 oauthtoken_invalid - Invalid OAuth token passed\..*credentials were rejected/);
});
await t('OAuth mode posts to the bot message API on the configured domain with the Zoho-oauthtoken header', async () => {
  const seen = [];
  const f = async (u, o) => { seen.push({ u: String(u), auth: o?.headers?.Authorization, body: o?.body }); return String(u).includes('/oauth/') ? new Response(JSON.stringify({ access_token: 'ACCESS1' }), { status: 200 }) : new Response('{}', { status: 200 }); };
  const r = createRelay({ cfg, secrets: { CLIQ_BOT: 'mybot', CLIQ_CLIENT_ID: 'c', CLIQ_CLIENT_SECRET: 's', CLIQ_REFRESH_TOKEN: 'r', CLIQ_ACCOUNTS: 'https://accounts.zoho.in', CLIQ_API: 'https://cliq.zoho.in' }, token, fetchImpl: f });
  await r.postCliq('hello');
  assert.equal(seen[0].u.split('?')[0], 'https://accounts.zoho.in/oauth/v2/token'); assert(seen[0].u.includes('grant_type=refresh_token'));
  assert.equal(seen[1].u, 'https://cliq.zoho.in/api/v2/bots/mybot/message'); assert.equal(seen[1].auth, 'Zoho-oauthtoken ACCESS1'); assert.equal(JSON.parse(seen[1].body).text, 'hello');
  await r.postCliq('again'); assert.equal(seen.filter((x) => x.u.includes('/oauth/')).length, 1, 'token not cached');
});

await t('CLIQ_WEBHOOK_TOKEN is appended as zapikey (once), and --check warns when an endpoint has no key', async () => {
  const seen = [];
  const f = async (u) => { seen.push(String(u)); return new Response('{}', { status: 200 }); };
  const r = createRelay({ cfg, secrets: { CLIQ_ENDPOINT: 'https://cliq.zoho.in/api/v2/bots/kbot/message', CLIQ_WEBHOOK_TOKEN: '1000.abc.def' }, token, fetchImpl: f });
  await r.postCliq('x');
  assert.equal(seen[0], 'https://cliq.zoho.in/api/v2/bots/kbot/message?zapikey=1000.abc.def');
  const r2 = createRelay({ cfg, secrets: { CLIQ_ENDPOINT: 'https://cliq.zoho.in/api/v2/bots/kbot/message?zapikey=K1', CLIQ_WEBHOOK_TOKEN: 'K2' }, token, fetchImpl: f });
  await r2.postCliq('y');
  assert.equal(seen[1], 'https://cliq.zoho.in/api/v2/bots/kbot/message?zapikey=K1');
  const bare = createRelay({ cfg, secrets: { CLIQ_ENDPOINT: 'https://cliq.zoho.in/api/v2/bots/kbot/message' }, token });
  assert.match((await bare.check()).problems.join(' '), /no zapikey.*Webhook Tokens/);
  const ok = createRelay({ cfg, secrets: { CLIQ_ENDPOINT: 'https://cliq.zoho.in/api/v2/bots/kbot/message', CLIQ_WEBHOOK_TOKEN: 'T' }, token });
  assert.equal((await ok.check()).problems.length, 0);
});

console.log = origLog; server.close();
out(`\n${pass} checks passed${process.exitCode ? ', SOME FAILED' : ''}. Stand-in Cliq received nothing real.`);
fs.rmSync(tmp, { recursive: true, force: true });
