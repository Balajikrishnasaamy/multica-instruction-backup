// Tests runLive (connect, login frame, catch-up on login, push handling, reconnect with backoff) against a local stand-in websocket server.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mcn-live-'));
process.env.MCN_CONF_DIR = path.join(tmp, 'conf'); process.env.MCN_STATE_DIR = path.join(tmp, 'state');
const { createRelay, runLive, loadConfig } = await import('./relay.mjs');

function frame(obj) { const p = Buffer.from(JSON.stringify(obj)); const h = p.length < 126 ? Buffer.from([0x81, p.length]) : Buffer.from([0x81, 126, p.length >> 8, p.length & 255]); return Buffer.concat([h, p]); }
function readFrame(buf) { let len = buf[1] & 127, off = 2; if (len === 126) { len = buf.readUInt16BE(2); off = 4; } const mask = buf.slice(off, off + 4); off += 4; const d = Buffer.alloc(len); for (let i = 0; i < len; i++) d[i] = buf[off + i] ^ mask[i % 4]; return d.toString(); }

const connections = []; const authFrames = [];
let itemToPush = null;
const wsServer = http.createServer();
wsServer.on('upgrade', (req, sock) => {
  const key = req.headers['sec-websocket-key'];
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')}\r\n\r\n`);
  const n = connections.push({ url: req.url, sock });
  sock.on('data', (b) => {
    if ((b[0] & 15) === 8) return sock.end();
    let m; try { m = JSON.parse(readFrame(b)); } catch { return; }
    if (m.type === 'auth') {
      authFrames.push(m.payload);
      sock.write(frame({ type: 'auth_ack' }));
      if (n === 1) setTimeout(() => { sock.write(frame({ type: 'task:message', payload: {} })); sock.write(frame({ type: 'inbox:new', payload: { item: itemToPush() } })); }, 150);
      if (n === 1) setTimeout(() => sock.destroy(), 700);          // drop the connection to force a reconnect
      if (n === 2) setTimeout(() => sock.write(frame({ type: 'inbox:new', payload: { item: itemToPush('second') } })), 150);
    }
  });
  sock.on('error', () => {});
});
await new Promise((r) => wsServer.listen(0, '127.0.0.1', r));

let cliqCalls = [];
const cliq = http.createServer((req, res) => { let b = ''; req.on('data', (d) => (b += d)); req.on('end', () => { cliqCalls.push(JSON.parse(b)); res.end('{}'); }); });
await new Promise((r) => cliq.listen(0, '127.0.0.1', r));

const { cfg, token } = loadConfig();
cfg.ws_url = `ws://127.0.0.1:${wsServer.address().port}/ws`; cfg.min_send_gap_ms = 20; cfg.poll_minutes = 60;
const relay = createRelay({ cfg, secrets: { CLIQ_ENDPOINT: `http://127.0.0.1:${cliq.address().port}/h?zapikey=K` }, token });
const me = await relay.getMe();
const inbox = await relay.api('/api/inbox');
const real = inbox.find((i) => i.type === 'mentioned' && i.recipient_id === me.id);
const pushed = new Set();
itemToPush = (tag = 'first') => { const it = { ...real, id: `live-${tag}-${Date.now()}`, created_at: new Date().toISOString(), archived: false }; pushed.add(it.id); return it; };

const stop = await runLive(relay, cfg);
await new Promise((r) => setTimeout(r, 6000));
stop();
let ok = 0; const chk = (n, f) => { try { f(); ok++; console.log('PASS ', n); } catch (e) { console.log('FAIL ', n, '->', e.message); process.exitCode = 1; } };
chk('connects with workspace slug in the URL', () => assert.match(connections[0].url, /workspace_slug=cirdoc/));
chk('the token goes in the first message, never in the URL', () => { assert(!connections[0].url.includes(token)); assert.equal(authFrames[0].token, token); });
chk('the first catch-up after login baselines existing mentions (no flood)', () => assert.equal(relay.state.baseline_done, true));
chk('a pushed mention is sent to Cliq, other frame types are ignored', () => assert.equal(cliqCalls.length >= 1, true));
chk('after the connection drops it reconnects and logs in again', () => { assert(connections.length >= 2, 'connections=' + connections.length); assert(authFrames.length >= 2); });
chk('a mention pushed on the second connection is also delivered', () => assert.equal(cliqCalls.length, 2, 'cliq calls=' + cliqCalls.length));
chk('every pushed item produced exactly one message (counted by item id, not by text)', () => { assert.equal(cliqCalls.length, pushed.size, `messages=${cliqCalls.length} items pushed=${pushed.size}`); });
console.log(`\n${ok} live checks passed`);
wsServer.close(); cliq.close(); fs.rmSync(tmp, { recursive: true, force: true }); setTimeout(() => process.exit(process.exitCode || 0), 100);
