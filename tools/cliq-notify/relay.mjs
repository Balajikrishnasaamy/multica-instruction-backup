#!/usr/bin/env node
// multica-cliq-notify: sends a Zoho Cliq message when YOU are @mentioned in Multica.
// No dependencies (Node 22+). Live push over Multica's websocket (the same `inbox:new` event the desktop app uses),
// plus a catch-up read of /api/inbox on start, after every reconnect, and every few minutes.
//
//   node relay.mjs                 run (live + catch-up)
//   node relay.mjs --check         verify config, token and Cliq settings; sends nothing
//   node relay.mjs --test-send     send one test message to Cliq
//   node relay.mjs --exchange-code turn the one-time Zoho code into CLIQ_REFRESH_TOKEN (saved to secrets.env, never printed)
//   node relay.mjs --dry-run       do everything except sending; print the messages instead
//   node relay.mjs --replay N      print the last N real mentions as Cliq messages (never sends, never records)
//   node relay.mjs --once          catch up once and exit
//   node relay.mjs --backfill N    on the very first run, also send the last N existing mentions (default 0)
//
// Secrets: ~/.config/multica-cliq/secrets.env (mode 600). Settings: ~/.config/multica-cliq/config.json. See SETUP.md.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const HOME = os.homedir();
export const CONF_DIR = process.env.MCN_CONF_DIR || path.join(HOME, '.config', 'multica-cliq');
export const STATE_DIR = process.env.MCN_STATE_DIR || path.join(HOME, '.local', 'state', 'multica-cliq');

const DEFAULTS = {
  api_url: 'https://api.multica.ai',
  ws_url: 'wss://api.multica.ai/ws',
  cli_profile: 'desktop-api.multica.ai',
  workspace_slug: 'cirdoc',
  workspace_id: '85121eb5-c9c7-4018-a975-140810c991cb',
  types: ['mentioned'],
  catchup_max_age_hours: 24,
  poll_minutes: 5,
  snippet_chars: 400,
  min_send_gap_ms: 1100,
  issue_url_template: 'https://multica.ai/{slug}/issues/{issue_id}',
};

const SECRET_RE = /((?:password|passwd|secret|token|privatekey|private_key|authtoken|apikey|api_key|zapikey|client[._]secret|bearer)[A-Za-z0-9_.]*\s*[=:]\s*)[^\s,;&"']+/gi;
export const mask = (s) => String(s ?? '')
  .replace(SECRET_RE, '$1****')
  .replace(/(zapikey=)[^&\s"']+/gi, '$1****')
  .replace(/(Bearer |Zoho-oauthtoken )[A-Za-z0-9._-]+/g, '$1****')
  .replace(/\bmul_[A-Za-z0-9]{20,}\b/g, 'mul_****');

const ts = () => new Date().toISOString().replace('T', ' ').slice(0, 19);
let LOG_FILE_ECHO = true;
export const log = (...a) => { if (LOG_FILE_ECHO) console.log(ts(), mask(a.join(' '))); };

export function loadEnvFile(file) {
  const out = {};
  let st;
  try { st = fs.statSync(file); } catch { return out; }
  if (st.mode & 0o077) log(`WARNING: ${file} is readable by other users (mode ${(st.mode & 0o777).toString(8)}); run: chmod 600 ${file}`);
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m || line.trim().startsWith('#')) continue;
    out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

export function loadConfig() {
  let file = {};
  try { file = JSON.parse(fs.readFileSync(path.join(CONF_DIR, 'config.json'), 'utf8')); } catch { /* defaults */ }
  const secrets = { ...loadEnvFile(path.join(CONF_DIR, 'secrets.env')) };
  for (const k of Object.keys(process.env)) if (/^(MULTICA_TOKEN|CLIQ_[A-Z_]+)$/.test(k)) secrets[k] = process.env[k];
  const cfg = { ...DEFAULTS, ...file };
  let token = secrets.MULTICA_TOKEN;
  let tokenSource = 'secrets.env';
  if (!token) {
    try {
      token = JSON.parse(fs.readFileSync(path.join(HOME, '.multica', 'profiles', cfg.cli_profile, 'config.json'), 'utf8')).token;
      tokenSource = `Multica CLI profile ${cfg.cli_profile} (read at run time, never copied)`;
    } catch { /* none */ }
  }
  const getToken = secrets.MULTICA_TOKEN ? null : () => { try { return JSON.parse(fs.readFileSync(path.join(HOME, '.multica', 'profiles', cfg.cli_profile, 'config.json'), 'utf8')).token; } catch { return null; } };
  return { cfg, secrets, token, tokenSource, getToken };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function createRelay({ cfg, secrets, token, getToken = null, dryRun = false, fetchImpl = fetch, now = () => Date.now() }) {
  let curToken = token;
  const H = () => ({ Authorization: `Bearer ${curToken}`, 'X-Workspace-ID': cfg.workspace_id, Accept: 'application/json' });
  function refreshToken() { if (!getToken) return false; const t = getToken(); if (t && t !== curToken) { curToken = t; log('Multica token changed on disk; using the new one'); return true; } return false; }
  const statePath = path.join(STATE_DIR, 'state.json');
  let state = { baseline_done: false, sent: [], last_catchup: null };
  try { state = { ...state, ...JSON.parse(fs.readFileSync(statePath, 'utf8')) }; } catch { /* first run */ }
  const sentSet = new Set(state.sent);
  let me = null;
  const cache = { issues: new Map(), agents: null, comments: new Map() };
  let queue = Promise.resolve();
  let lastSend = 0;
  let oauth = { token: null, exp: 0 };
  const stats = { sent: 0, skipped: 0, failed: 0 };

  function saveState() {
    fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
    state.sent = [...sentSet].slice(-3000);
    const tmp = statePath + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
    fs.renameSync(tmp, statePath);
  }

  async function api(p) {
    let r = await fetchImpl(cfg.api_url + p, { headers: H(), signal: AbortSignal.timeout(30000) });
    if (r.status === 401 && refreshToken()) r = await fetchImpl(cfg.api_url + p, { headers: H(), signal: AbortSignal.timeout(30000) });
    if (!r.ok) { const e = new Error(`GET ${p.split('?')[0]} -> ${r.status}`); e.status = r.status; throw e; }
    return r.json();
  }
  async function getMe() { return (me ??= await api('/api/me')); }
  async function getIssue(id) {
    if (!cache.issues.has(id)) cache.issues.set(id, await api(`/api/issues/${id}`));
    return cache.issues.get(id);
  }
  async function agentName(id) {
    if (!cache.agents || !cache.agents.has(id)) {
      const list = await api('/api/agents');
      cache.agents = new Map(list.map((a) => [a.id, a.name]));
    }
    return cache.agents.get(id) || 'someone';
  }
  async function getComment(issueId, commentId) {
    const c = cache.comments.get(issueId);
    let list;
    if (c && now() - c.t < 20000 && c.list.some((x) => x.id === commentId)) list = c.list;
    else {
      const j = await api(`/api/issues/${issueId}/comments`);
      list = Array.isArray(j) ? j : j.comments || [];
      cache.comments.set(issueId, { t: now(), list });
    }
    return list.find((x) => x.id === commentId) || null;
  }

  function snippet(text) {
    let s = String(text || '')
      .replace(/\[(@[^\]]+)\]\(mention:\/\/[^)]+\)/g, '$1')
      .replace(/```[\s\S]*?```/g, ' [code] ')
      .replace(/\r/g, '')
      .replace(/\n{2,}/g, '\n')
      .trim();
    s = mask(s);
    const max = cfg.snippet_chars;
    if (s.length > max) s = s.slice(0, max).replace(/\s+\S*$/, '') + ' ...';
    return s;
  }

  async function buildMessage(item) {
    const [issue, actor, comment] = await Promise.all([
      getIssue(item.issue_id),
      item.actor_type === 'agent' ? agentName(item.actor_id) : Promise.resolve('A teammate'),
      item.details?.comment_id ? getComment(item.issue_id, item.details.comment_id).catch(() => null) : null,
    ]);
    const url = cfg.issue_url_template.replace('{slug}', cfg.workspace_slug).replace('{issue_id}', item.issue_id).replace('{identifier}', issue.identifier);
    const title = String(issue.title || item.title || '').replace(/\s+/g, ' ').slice(0, 120);
    const lines = [`*${actor}* mentioned you on *${issue.identifier}*: ${title}`];
    if (cfg.snippet_chars > 0 && comment?.content) lines.push('', snippet(comment.content));
    lines.push('', `Issue: ${issue.identifier}   (search this in the Multica app)`);
    return { text: lines.join('\n'), identifier: issue.identifier, url };
  }

  // ---------- Cliq sink ----------
  async function oauthToken() {
    if (oauth.token && now() < oauth.exp) return oauth.token;
    const q = new URLSearchParams({ refresh_token: secrets.CLIQ_REFRESH_TOKEN, client_id: secrets.CLIQ_CLIENT_ID, client_secret: secrets.CLIQ_CLIENT_SECRET, grant_type: 'refresh_token' });
    const r = await fetchImpl(`${secrets.CLIQ_ACCOUNTS || 'https://accounts.zoho.com'}/oauth/v2/token?${q}`, { method: 'POST', signal: AbortSignal.timeout(30000) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.access_token) { const e = new Error(`Zoho token refresh failed: HTTP ${r.status} ${mask(JSON.stringify(j)).slice(0, 160)}${j.error === 'invalid_client' ? ' (client id/secret do not match the accounts domain: check CLIQ_ACCOUNTS)' : j.error === 'invalid_code' ? ' (the refresh token is wrong or revoked: run --exchange-code again)' : ''}`); e.fatal = true; throw e; }
    oauth = { token: j.access_token, exp: now() + 50 * 60 * 1000 };
    return oauth.token;
  }
  function cliqConfigured() {
    if (secrets.CLIQ_ENDPOINT) return 'endpoint';
    if (secrets.CLIQ_CLIENT_ID && secrets.CLIQ_CLIENT_SECRET && secrets.CLIQ_REFRESH_TOKEN && secrets.CLIQ_BOT) return 'oauth';
    return null;
  }
  async function postCliq(text) {
    const mode = cliqConfigured();
    if (!mode) { const e = new Error('Cliq is not configured (set CLIQ_ENDPOINT, or the CLIQ_CLIENT_ID/SECRET/REFRESH_TOKEN/BOT set, in secrets.env)'); e.fatal = true; throw e; }
    const body = { text };
    if (secrets.CLIQ_USER_IDS) body.userids = secrets.CLIQ_USER_IDS;
    const headers = { 'Content-Type': 'application/json' };
    let url;
    if (mode === 'endpoint') {
      url = secrets.CLIQ_ENDPOINT;
      if (secrets.CLIQ_WEBHOOK_TOKEN && !/[?&]zapikey=/.test(url)) url += (url.includes('?') ? '&' : '?') + 'zapikey=' + encodeURIComponent(secrets.CLIQ_WEBHOOK_TOKEN);
    }
    else {
      url = `${secrets.CLIQ_API || 'https://cliq.zoho.com'}/api/v2/bots/${encodeURIComponent(secrets.CLIQ_BOT)}/message`;
      headers.Authorization = `Zoho-oauthtoken ${await oauthToken()}`;
    }
    const r = await fetchImpl(url, { method: 'POST', headers, body: JSON.stringify(body), signal: AbortSignal.timeout(30000) });
    if (r.status >= 200 && r.status < 300) return { status: r.status };
    const raw = (await r.text().catch(() => '')).slice(0, 300);
    let detail = raw;
    // joined with ' - ' (not ': '), or the secret masker would read an error code such as oauthtoken_invalid as a key name
    try { const j = JSON.parse(raw); detail = [j.code, j.message].filter(Boolean).join(' - ') || raw; } catch { /* plain text */ }
    detail = mask(detail);
    const hint = r.status === 401 ? ' (the credentials were rejected: for the OAuth route re-run --check; for an endpoint URL it needs its key)'
      : r.status === 404 ? ' (bot name or URL not found)' : r.status === 403 ? ' (the token lacks the ZohoCliq.Webhooks.CREATE scope, or you are not subscribed to the bot)' : '';
    const e = new Error(`Cliq answered HTTP ${r.status}${detail ? ' ' + detail : ''}${hint}`);
    e.status = r.status;
    e.fatal = r.status === 400 || r.status === 401 || r.status === 403 || r.status === 404;
    throw e;
  }
  async function sendWithRetry(text) {
    const wait = Math.max(0, lastSend + cfg.min_send_gap_ms - now());
    if (wait) await sleep(wait);
    let lastErr;
    for (let attempt = 1; attempt <= 4; attempt++) {
      try { const r = await postCliq(text); lastSend = now(); return r; }
      catch (e) {
        lastErr = e;
        if (e.fatal) break;
        await sleep(Math.min(8000, 500 * 2 ** attempt));
      }
    }
    lastSend = now();
    throw lastErr;
  }

  // ---------- handling ----------
  function wanted(item) {
    return item && cfg.types.includes(item.type) && !item.archived;
  }
  async function deliver(item, { record = true } = {}) {
    const m = await getMe();
    if (!wanted(item) || item.recipient_id !== m.id) { stats.skipped++; return 'skipped'; }
    if (sentSet.has(item.id)) { stats.skipped++; return 'duplicate'; }
    const msg = await buildMessage(item);
    if (dryRun) {
      console.log(`\n----- DRY RUN: would send to Cliq (${item.id.slice(0, 8)}) -----\n${msg.text}\n-----`);
      return 'dry-run';
    }
    try {
      await sendWithRetry(msg.text);
    } catch (e) {
      stats.failed++;
      log(`FAILED to deliver ${msg.identifier} (${item.id.slice(0, 8)}): ${e.message}${e.fatal ? ' [not retried: fix the Cliq settings]' : ' [will retry at the next catch-up]'}`);
      return 'failed';
    }
    stats.sent++;
    if (record) { sentSet.add(item.id); saveState(); }
    log(`sent ${msg.identifier} mention ${item.id.slice(0, 8)} to Cliq`);
    return 'sent';
  }
  function enqueue(fn) {
    const run = queue.then(fn, fn);
    queue = run.catch(() => {});
    return run;
  }

  async function catchUp({ backfill = 0 } = {}) {
    const m = await getMe();
    const inbox = await api('/api/inbox');
    const mine = inbox.filter((i) => wanted(i) && i.recipient_id === m.id).sort((a, b) => a.created_at.localeCompare(b.created_at));
    if (!state.baseline_done && !dryRun) {
      const keep = backfill > 0 ? mine.slice(-backfill) : [];
      for (const i of mine) if (!keep.includes(i)) sentSet.add(i.id);
      state.baseline_done = true;
      saveState();
      log(`first run: marked ${mine.length - keep.length} existing mention(s) as already seen${keep.length ? `; sending the last ${keep.length}` : ''}`);
      for (const i of keep) await enqueue(() => deliver(i));
      return;
    }
    const cutoff = now() - cfg.catchup_max_age_hours * 3600 * 1000;
    let pending = mine.filter((i) => !sentSet.has(i.id) && Date.parse(i.created_at) >= cutoff);
    if (dryRun && pending.length > 3) { log(`dry-run: ${pending.length} pending mention(s); showing only the newest 3`); pending = pending.slice(-3); }
    if (pending.length) log(`catch-up: ${pending.length} mention(s) not yet sent`);
    for (const i of pending) await enqueue(() => deliver(i));
    state.last_catchup = new Date(now()).toISOString();
    if (!dryRun) saveState();
  }

  // a websocket frame (already parsed). Exported for tests.
  async function handleFrame(msg) {
    if (msg && msg.type === 'inbox:new' && msg.payload?.item) return enqueue(() => deliver(msg.payload.item));
    return null;
  }

  async function check() {
    const problems = [];
    const out = [];
    try { const m = await getMe(); out.push(`Multica login OK as ${m.name} <${m.email}>`); } catch (e) { problems.push(`Multica login failed: ${e.message}`); }
    out.push(`Multica token from: ${'(see config)'}`);
    const mode = cliqConfigured();
    if (!mode) {
      const need = ['CLIQ_BOT', 'CLIQ_CLIENT_ID', 'CLIQ_CLIENT_SECRET', 'CLIQ_REFRESH_TOKEN'];
      const have = need.filter((k) => secrets[k]);
      if (have.length) problems.push(`Cliq OAuth is incomplete. Missing in secrets.env: ${need.filter((k) => !secrets[k]).join(', ')}` + (!secrets.CLIQ_REFRESH_TOKEN && secrets.CLIQ_CLIENT_ID ? '  (get the refresh token with: node relay.mjs --exchange-code)' : ''));
      else problems.push('Cliq is not configured yet (see SETUP.md step 3)');
    } else out.push(`Cliq sink: ${mode === 'endpoint' ? 'bot endpoint URL (CLIQ_ENDPOINT)' : 'OAuth + bot ' + secrets.CLIQ_BOT}`);
    if (mode === 'endpoint' && !/[?&]zapikey=/.test(secrets.CLIQ_ENDPOINT) && !secrets.CLIQ_WEBHOOK_TOKEN) problems.push('CLIQ_ENDPOINT has no zapikey. Generate a Webhook Token in Cliq (Bots & Tools > Webhook Tokens) and put it in secrets.env as CLIQ_WEBHOOK_TOKEN=<token>');
    if (mode === 'oauth') {
      try { await oauthToken(); out.push('Zoho accepted the refresh token (access token obtained)'); }
      catch (e) { problems.push(e.message); }
    }
    out.push(`Mention types sent to Cliq: ${cfg.types.join(', ')}`);
    return { out, problems };
  }

  return { refreshToken, token: () => curToken, catchUp, handleFrame, deliver, check, postCliq, sendWithRetry, getMe, api, enqueue, stats, state, sentSet, cliqConfigured, buildMessage, saveState,
    idle: () => queue };
}


// Turns the one-time code from the Zoho API console (Self Client > Generate Code) into a refresh token and writes it into
// secrets.env (mode 600). The token is never printed.
export async function exchangeCode({ secrets, code, fetchImpl = fetch, secretsFile = path.join(CONF_DIR, 'secrets.env') }) {
  for (const k of ['CLIQ_CLIENT_ID', 'CLIQ_CLIENT_SECRET']) if (!secrets[k]) throw new Error(`${k} is missing in ${secretsFile}`);
  code = String(code || '').trim();
  if (!/^1000\.[0-9a-f]+\.[0-9a-f]+$/i.test(code)) throw new Error('that does not look like a Zoho code (expected 1000.<hex>.<hex>)');
  const q = new URLSearchParams({ grant_type: 'authorization_code', client_id: secrets.CLIQ_CLIENT_ID, client_secret: secrets.CLIQ_CLIENT_SECRET, code });
  const r = await fetchImpl(`${secrets.CLIQ_ACCOUNTS || 'https://accounts.zoho.com'}/oauth/v2/token?${q}`, { method: 'POST', signal: AbortSignal.timeout(30000) });
  const j = await r.json().catch(() => ({}));
  if (!j.refresh_token) {
    const why = j.error === 'invalid_code' ? 'the code was already used or has expired (the default lifetime is 3 minutes and it works once): generate a new one'
      : j.error === 'oauth_app_blocked' ? 'Zoho answered oauth_app_blocked for this client. The cause is not known from here (an organisation admin policy, or a temporary block after repeated failed attempts). Wait a while and retry once with a fresh code; if it persists, ask your Zoho admin to unblock the client or use the bot webhook URL instead (SETUP.md option A)'
      : j.error === 'invalid_client' ? 'client id/secret rejected: check them, and that CLIQ_ACCOUNTS matches your Zoho region'
      : j.error ? `Zoho said: ${j.error}` : `HTTP ${r.status}, no refresh token in the answer (did the code use the ZohoCliq.Webhooks.CREATE scope?)`;
    throw new Error(`token exchange failed: ${why}`);
  }
  const line = `CLIQ_REFRESH_TOKEN=${j.refresh_token}`;
  let text = ''; try { text = fs.readFileSync(secretsFile, 'utf8'); } catch { /* new file */ }
  text = /^\s*CLIQ_REFRESH_TOKEN\s*=.*$/m.test(text) ? text.replace(/^\s*CLIQ_REFRESH_TOKEN\s*=.*$/m, line) : (text.replace(/\n*$/, '\n') + line + '\n');
  const tmp = secretsFile + '.tmp';
  fs.writeFileSync(tmp, text, { mode: 0o600 });
  fs.renameSync(tmp, secretsFile);
  fs.chmodSync(secretsFile, 0o600);
  return { scope: j.scope || null };
}

// ---------- websocket runner ----------
export async function runLive(relay, cfg) {
  let attempt = 0;
  let stopped = false;
  const connect = () => {
    if (stopped) return;
    const url = `${cfg.ws_url}?workspace_slug=${encodeURIComponent(cfg.workspace_slug)}&client_platform=cliq-notify`;
    const ws = new WebSocket(url);
    let authed = false;
    ws.onopen = () => ws.send(JSON.stringify({ type: 'auth', payload: { token: relay.token() } }));
    ws.onmessage = async (e) => {
      let m; try { m = JSON.parse(e.data); } catch { return; }
      if (!m || typeof m.type !== 'string') return;
      if (m.type === 'auth_ack') {
        authed = true; attempt = 0;
        log('live connection established');
        relay.catchUp().catch((err) => log('catch-up failed:', err.message));
        return;
      }
      relay.handleFrame(m).catch((err) => log('handling failed:', err.message));
    };
    ws.onerror = () => {};
    ws.onclose = (e) => {
      if (stopped) return;
      const delay = Math.min(60000, 1000 * 2 ** attempt) * (0.7 + Math.random() * 0.6);
      attempt++;
      relay.refreshToken();
      log(`live connection closed (code ${e.code}${authed ? '' : ', before login'}); reconnecting in ${Math.round(delay / 1000)}s`);
      setTimeout(connect, delay);
    };
  };
  connect();
  const poll = setInterval(() => relay.catchUp().catch((err) => log('periodic catch-up failed:', err.message)), cfg.poll_minutes * 60000);
  return () => { stopped = true; clearInterval(poll); };
}

// ---------- CLI ----------
async function main() {
  const argv = process.argv.slice(2);
  const has = (f) => argv.includes(f);
  const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : undefined; };
  const { cfg, secrets, token, tokenSource, getToken } = loadConfig();
  if (!token) { console.error('No Multica token: install/login the Multica CLI, or set MULTICA_TOKEN in secrets.env'); process.exit(2); }
  const dryRun = has('--dry-run') || has('--replay');
  const relay = createRelay({ cfg, secrets, token, getToken, dryRun });

  if (has('--check')) {
    const { out, problems } = await relay.check();
    console.log(out.join('\n').replace('(see config)', tokenSource));
    console.log(`Config dir: ${CONF_DIR}\nState dir:  ${STATE_DIR}`);
    if (problems.length) { console.log('\nTO FIX:\n - ' + problems.join('\n - ')); process.exit(1); }
    console.log('\nAll good. Run --test-send to confirm the message reaches Cliq.');
    return;
  }
  if (has('--exchange-code')) {
    let code = process.env.CLIQ_GRANT_CODE || val('--exchange-code');
    if (!code || code.startsWith('--')) {
      const rl = (await import('node:readline')).createInterface({ input: process.stdin, output: process.stdout });
      code = await new Promise((res) => rl.question('Paste the code from the Zoho API console (1000.xxxx.xxxx) and press Enter: ', (a) => { rl.close(); res(a); }));
    }
    try { await exchangeCode({ secrets, code }); console.log(`Saved CLIQ_REFRESH_TOKEN to ${path.join(CONF_DIR, 'secrets.env')} (mode 600). Now run: node relay.mjs --check`); }
    catch (e) { console.error('FAILED:', mask(e.message)); process.exit(1); }
    return;
  }
  if (has('--test-send')) {
    if (!relay.cliqConfigured()) { console.error('Cliq is not configured yet (SETUP.md step 3)'); process.exit(1); }
    try { const r = await relay.sendWithRetry('Multica to Cliq: test message. If you can read this, mention notifications will arrive here.'); console.log(`sent, Cliq answered HTTP ${r.status}`); }
    catch (e) { console.error('FAILED:', e.message); process.exit(1); }
    return;
  }
  if (has('--replay')) {
    const n = parseInt(val('--replay') || '3', 10);
    const m = await relay.getMe();
    const inbox = await relay.api('/api/inbox');
    const mine = inbox.filter((i) => cfg.types.includes(i.type) && i.recipient_id === m.id).sort((a, b) => a.created_at.localeCompare(b.created_at)).slice(-n);
    for (const i of mine) await relay.deliver(i, { record: false });
    return;
  }
  const backfill = parseInt(val('--backfill') || '0', 10);
  log(`starting: types=${cfg.types.join(',')} dry-run=${dryRun} cliq=${relay.cliqConfigured() || 'NOT CONFIGURED'}`);
  await relay.catchUp({ backfill }).catch((e) => log('initial catch-up failed:', e.message));
  await relay.idle();
  if (has('--once')) return;
  const stop = await runLive(relay, cfg);
  const bye = () => { stop(); log('stopping'); setTimeout(() => process.exit(0), 200); };
  process.on('SIGINT', bye); process.on('SIGTERM', bye);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(mask(e.stack || e.message)); process.exit(1); });
}
