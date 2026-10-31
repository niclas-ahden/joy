// Node harness for picking up after a page reload (saveSessions and `resume` in
// www/hot.js): an app saves its session, the page goes, and the next mount of a
// module replays it. tests/apps/hot_page_v1.roc to hot_page_v3.roc are three
// builds of one app. A hot reload without a page reload is tests/check_hot.mjs.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_sessions.mjs
import { readFileSync } from 'node:fs';
import { mock } from 'node:test';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, FakeFile, fakeDom, modalCalls } from './fakedom.mjs';
import { expect, hotWasmPath, plainWasmPath } from './harness.mjs';

const hot = globalThis.__JOY_HOT__;
const page = (n) => readFileSync(hotWasmPath(`hot_page_v${n}`));

mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });
const flush = () => new Promise((resolve) => setImmediate(resolve));
// Compression and the replay's own waiting take turns of the event loop.
const settle = async () => { for (let i = 0; i < 20; i++) await flush(); };

// sessionStorage as a browser has it, which node does not.
const stored = new Map();
let refuseWrites = false;
globalThis.sessionStorage = {
  getItem: (key) => stored.get(key) ?? null,
  setItem: (key, value) => {
    if (refuseWrites) throw new DOMException('full', 'QuotaExceededError');
    stored.set(key, value);
  },
  removeItem: (key) => stored.delete(key),
};

// Each "METHOD url" sent, answered at once with the body `answers` holds.
const sent = [];
const answers = new Map();
globalThis.fetch = async (url, opts) => {
  sent.push(`${opts?.method ?? 'GET'} ${url}`);
  const body = answers.get(url) ?? `first answer from ${url}`;
  return {
    status: 200,
    headers: new Map(),
    arrayBuffer: async () => new TextEncoder().encode(body).buffer,
  };
};
const sentTo = (what) => sent.filter((one) => one === what).length;

// What the console was told, by level.
const told = { info: [], warn: [], error: [] };
for (const level of Object.keys(told)) console[level] = (...args) => told[level].push(args.join(' '));
const heard = (level, text) => told[level].filter((line) => line.includes(text)).length;

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};
const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

// Mount a module on a page of its own, the way a page load does. Whatever session
// is saved is picked up.
async function start(wasm, flags = 'first boot') {
  for (const level of Object.keys(told)) told[level].length = 0;
  sent.length = 0;
  const root = new El('#root');
  const app = await mount({ wasm, root, flags, dom: fakeDom });
  await settle();
  const el = (id) => byId(root, id);
  return {
    app,
    el,
    read: (id) => textOf(el(id)),
    click: (id) => el(id).listeners.click(),
    type: (id, value) => el(id).listeners.input({ target: { value } }),
  };
}

// What a page does on its way out, without the page going anywhere.
async function leave(t) {
  await hot.saveSessions();
  await settle();
  t.app.unmount();
}

// --- A session comes back, from every kind of input ---
{
  const t = await start(page(1));
  t.click('inc');
  t.click('inc');
  t.type('name', 'Ada');
  t.click('later');
  mock.timers.tick(5);
  await flush();
  t.el('field').listeners.keydown({ key: 'Enter', code: 'Enter' });
  t.el('pad').listeners.pointerdown({ clientX: 12 });
  expect('every input: the first page got there', `${t.read('count')}|${t.read('fired')}|${t.read('key')}|${t.read('x')}`, '2|1|Enter|12');
  await leave(t);
  expect('every input: the session is saved', stored.size, 1);

  const next = await start(page(1), 'second boot');
  expect('every input: the count', next.read('count'), '2');
  expect('every input: the typed text', next.el('name').value ?? next.el('name').attrs.get('value'), 'Ada');
  expect('every input: the timer, whose bytes went through storage', next.read('fired'), '1');
  expect('every input: the key', next.read('key'), 'Enter');
  expect('every input: the pointer', next.read('x'), '12');
  expect('every input: flags come from the new page', next.read('boots'), 'second boot');
  expect('every input: the console says so', heard('info', 'replayed 7 messages'), 1);
  expect('every input: nothing went wrong', `${told.warn.length}|${told.error.length}`, '0|0');
  expect('every input: a session is read once', stored.size, 0);
  next.click('inc');
  expect('every input: the page carries on', next.read('count'), '3');
  expect('every input: and records on', hot.session(next.app).flatMap((entry) => entry.msgs).length, 8);
  next.app.unmount();
}

// --- What a command left is put back, the dialog and the title and the URL ---
{
  const t = await start(page(1));
  t.click('inc');
  t.click('open');
  t.click('move');
  const before = modalCalls.length;
  await leave(t);
  // The page reloads at the URL its session started on.
  fakeDom.replaceUrl('/');
  const next = await start(page(1));
  expect('commands: the dialog opens again', next.el('dlg').open, true);
  expect('commands: only once', modalCalls.length - before, 1);
  expect('commands: the URL it had moved to', fakeDom.currentUrl(), '/moved');
  next.app.unmount();
}

// --- The new server's answers go in, and the old ones are not saved ---
{
  const t = await start(page(1));
  answers.set('/load', `old ${'x'.repeat(200_000)}`);
  t.click('load');
  await settle();
  t.click('inc');
  await leave(t);
  expect('answers: the body stays out of storage', [...stored.values()][0].length < 2_000, true);
  answers.set('/load', 'from the new server');
  const next = await start(page(1));
  expect('answers: sent again, once', sentTo('GET /load'), 1);
  expect('answers: the new answer goes in', next.read('data'), 'from the new server');
  expect('answers: and the replay goes on past it', next.read('count'), '1');
  expect('answers: every message came back', heard('info', 'replayed 3 messages'), 1);
  // The new answer is recorded in place of the old one, so a hot reload after
  // this replays it without asking again.
  sent.length = 0;
  const r = await next.app.reload(page(1));
  expect('answers: a hot reload after it needs no request', `${sent.length}|${next.read('data')}|${r.stopped}`, '0|from the new server|null');
  answers.delete('/load');
  next.app.unmount();
}

// --- A request that writes is never sent twice ---
// The replay meets the POST only after it has sent the GET, then starts over to
// stop before it, and that must not send the GET again.
{
  const t = await start(page(1));
  t.click('inc');
  t.click('load');
  await settle();
  t.click('save');
  await settle();
  t.click('inc');
  expect('POST: the first page wrote', `${sentTo('POST /save')}|${t.read('count')}`, '1|2');
  await leave(t);
  const next = await start(page(1));
  expect('POST: not sent again', sentTo('POST /save'), 0);
  expect('POST: the GET before it, once', sentTo('GET /load'), 1);
  expect('POST: stops before it', `${next.read('count')}|${next.read('saved')}`, '1|');
  expect('POST: what came before is there', next.read('data'), 'first answer from /load');
  expect('POST: the console says why', heard('warn', 'stopped before POST /save, so it is not sent twice'), 1);
  next.click('save');
  await settle();
  expect('POST: the page carries on, and can send it itself', `${sentTo('POST /save')}|${next.read('saved')}`, '1|first answer from /save');
  next.app.unmount();
}

// --- A GET the session never sent is sent, and the replay stops after it ---
{
  const t = await start(page(1));
  t.click('inc');
  t.click('inc');
  await leave(t);
  const next = await start(page(2));
  expect('new GET: sent, once', sentTo('GET /new'), 1);
  expect('new GET: stops after the message that asked', next.read('count'), '1');
  expect('new GET: the console says so', heard('warn', 'stopped after GET /new'), 1);
  expect('new GET: its answer reaches the app', next.read('data'), 'first answer from /new');
  next.app.unmount();
}

// --- What does not survive a reload stops the replay ---
{
  const t = await start(page(1));
  t.click('inc');
  const upload = t.el('upload');
  upload.fakeFile = new FakeFile('notes.txt', 'hi');
  upload.listeners.change({ target: upload });
  t.click('inc');
  expect('file: the first page had it', t.read('file'), 'notes.txt');
  await leave(t);
  const next = await start(page(1));
  expect('file: stops before it', `${next.read('count')}|${next.read('file')}`, '1|');
  expect('file: the console says why', heard('warn', 'a file or a recording'), 1);
  next.app.unmount();
}
{
  const t = await start(page(1));
  t.click('inc');
  hot.session(t.app).push({ op: 'dispatchBytes', via: 'joy/media/finish', args: new Uint8Array(), inputs: [new Uint8Array([1])], msgs: [{ hash: [0, 0, 0, 0], ambiguous: false, text: 'Recorded' }] });
  await leave(t);
  const next = await start(page(1));
  expect('recording: stops before it', `${next.read('count')}|${heard('warn', 'stopped at Recorded')}`, '1|1');
  next.app.unmount();
}

// --- The new build crashes on a message it replays ---
{
  const t = await start(page(1));
  t.click('inc');
  t.click('inc');
  await leave(t);
  const next = await start(page(3));
  expect('crash: picks up just before the message that crashed it', next.read('count'), '1');
  expect('crash: the console says so', heard('error', 'crashed on a replayed message'), 1);
  next.app.unmount();
}

// --- A session that cannot be saved or read starts the page over ---
{
  const t = await start(page(1));
  t.click('inc');
  refuseWrites = true;
  await hot.saveSessions();
  refuseWrites = false;
  expect('full: the console says so', heard('warn', 'did not fit in sessionStorage'), 1);
  expect('full: nothing is saved', stored.size, 0);
  t.app.unmount();
  const next = await start(page(1));
  expect('full: the next page starts over', next.read('count'), '0');
  next.app.unmount();
}
{
  const t = await start(page(1));
  t.click('inc');
  await leave(t);
  const [key] = stored.keys();
  stored.set(key, btoa('not what was saved'));
  const next = await start(page(1));
  expect('corrupt: the console says so', heard('warn', 'could not be read'), 1);
  expect('corrupt: the page starts over', next.read('count'), '0');
  next.click('inc');
  expect('corrupt: and works', next.read('count'), '1');
  expect('corrupt: and records', hot.session(next.app).length, 1);
  next.app.unmount();
}

// --- The replay cannot run at all: the page starts as if it had no session ---
{
  const t = await start(page(1));
  t.click('inc');
  await leave(t);
  const instantiate = WebAssembly.instantiate;
  let calls = 0;
  WebAssembly.instantiate = (...args) => {
    calls++;
    return calls > 1 ? Promise.reject(new Error('no second instance')) : instantiate(...args);
  };
  const next = await start(page(1));
  WebAssembly.instantiate = instantiate;
  expect('no replay: the console says so', heard('error', 'no second instance'), 1);
  expect('no replay: the page runs from the start', next.read('count'), '0');
  next.click('inc');
  expect('no replay: and works', next.read('count'), '1');
  expect('no replay: and records', hot.session(next.app).length, 1);
  next.app.unmount();
}

// --- 'skip' carries on past what is gone, and still never writes twice ---
{
  const t = await start(page(1));
  t.click('save');
  await settle();
  t.click('inc');
  await leave(t);
  hot.replay = 'skip';
  const next = await start(page(1));
  hot.replay = 'stop';
  expect('skip: the POST still stops it', `${sentTo('POST /save')}|${next.read('count')}`, '0|0');
  next.app.unmount();
}

// --- A page with nothing to pick up ---
{
  const t = await start(page(1));
  await leave(t);
  expect('empty: an app nothing happened in saves nothing', stored.size, 0);
  const plain = await start(readFileSync(plainWasmPath('hot_page_v1')));
  expect('plain: a build that does not record has no session', hot.session(plain.app), null);
  plain.click('inc');
  await leave(plain);
  expect('plain: and saves nothing', stored.size, 0);
}

// --- Which apps a rebuild reaches ---
{
  const on = (dataset) => Object.assign(new El('#root'), { dataset });
  const wasm = page(1);
  const nested = await mount({ wasm, root: on({ joyBundle: 'Shop/cart' }), flags: '', dom: fakeDom });
  const other = await mount({ wasm, root: on({ joyBundle: 'other' }), flags: '', dom: fakeDom });
  const fetched = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: true, headers: new Map(), arrayBuffer: async () => wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength) });
  const hand = await mount({ wasm: '/Shop/cart/app.wasm?v=1', root: new El('#root'), flags: '', dom: fakeDom });
  const elsewhere = await mount({ wasm: '/Other/app.wasm', root: new El('#root'), flags: '', dom: fakeDom });
  globalThis.fetch = fetched;
  const names = new Map([[nested, 'nested'], [other, 'other'], [hand, 'hand'], [elsewhere, 'elsewhere']]);
  const reached = (id) => hot.appsOf(id).map((app) => names.get(app)).join(',');
  expect('reach: a nested bundle, and an app mounted by hand from its module', reached('Shop/cart'), 'nested,hand');
  expect('reach: another bundle', reached('other'), 'other');
  expect('reach: a part of a nested id reaches nothing', reached('Shop'), '');
  for (const app of names.keys()) app.unmount();
}

// --- A dialog the user closed stays closed through a hot reload ---
// A native close, with Escape say, is not a message, so the session still ends
// with the dialog open, and the replay must leave the page's say alone.
{
  const t = await start(page(1));
  t.click('open');
  t.el('dlg').open = false;
  await t.app.reload(page(1));
  expect('closed dialog: stays closed', t.el('dlg').open, false);
  t.app.unmount();
}
