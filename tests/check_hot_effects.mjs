// Node harness for what a hot reload (www/hot.js) does with the effects an
// app has in flight, with messages too long to keep whole, and when it
// fails. tests/apps/hot_fx_v1.roc and hot_fx_v2.roc are two builds of one app
// with a request, a timer, a debounce and a digest to leave in flight, v2
// asking for requests v1 does not. hot_init_crash.roc is a build whose init
// crashes. tests.roc builds them with JOY_HOT. How a reload replays a
// session is tests/check_hot.mjs.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_effects.mjs
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { mock } from 'node:test';
const { makeRuntime, mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
// Joy's dev module, which hot reloads every app mounted after it and gives it
// app.reload, exactly as in a page the dev server serves.
import '../www/hot.js';
import { El, countTextReads, fakeDom } from './fakedom.mjs';
import { expect, hotWasmPath, plainWasmPath } from './harness.mjs';

const hot = globalThis.__JOY_HOT__;
const fx = (n) => readFileSync(hotWasmPath(`hot_fx_v${n}`));

// Timers and the clock are node:test's, so a check says how much time passes
// and nothing waits for it. `flush` lets what is already settled run, which
// needs no timer.
mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });
const flush = () => new Promise((resolve) => setImmediate(resolve));
const pass = async (ms) => {
  mock.timers.tick(ms);
  await flush();
};

// Each instance's calls to drop_call_cb, the host's release of a timer
// callback that never fires, by the instance the app hands out: a release
// missed leaks, and one too many frees what the host still holds.
const drops = new WeakMap();
const instantiate = WebAssembly.instantiate;
WebAssembly.instantiate = async (...args) => {
  const real = await instantiate(...args);
  const calls = [];
  const instance = {
    exports: { ...real.exports, drop_call_cb: (cb) => { calls.push(cb); real.exports.drop_call_cb(cb); } },
  };
  drops.set(instance, calls);
  return instance;
};

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};
const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

// Requests stay unanswered until `answer`, or `fail`, the way a network error
// ends one. `sent` has each "METHOD url". A response body is the `body` for
// its URL, a greeting in the language a request accepts, or names the URL.
const sent = [];
const unanswered = [];
const body = new Map();
globalThis.fetch = (url, opts) => {
  sent.push(`${opts?.method ?? 'GET'} ${url}`);
  const language = opts?.headers?.['Accept-Language'];
  const text = language ? `hello in ${language}` : `quote from ${url}`;
  return new Promise((resolve, reject) => unanswered.push({
    respond: () => resolve({
      status: 200,
      headers: new Headers(),
      arrayBuffer: async () => (body.get(url) ?? new TextEncoder().encode(text)).buffer,
    }),
    fail: () => reject(new TypeError('Failed to fetch')),
  }));
};
const answer = async () => {
  for (const request of unanswered.splice(0)) request.respond();
  await flush();
};
const fail = async () => {
  for (const request of unanswered.splice(0)) request.fail();
  await flush();
};
const sentTo = (line) => sent.filter((s) => s === line).length;

// A fresh app on a root of its own, with nothing left in flight from the one
// before and the request log cleared.
async function start(wasm) {
  await answer();
  await pass(10_000);
  sent.length = 0;
  const root = new El('#root');
  const app = await mount({ wasm, root, flags: '', dom: fakeDom });
  const el = (id) => byId(root, id);
  return {
    app,
    el,
    read: (id) => textOf(el(id)),
    click: (id) => el(id).listeners.click(),
    type: (id, value) => el(id).listeners.input({ target: { value } }),
    // How many recorded messages start with `text`.
    recorded: (text) => hot.session(app).flatMap((entry) => entry.msgs).filter((msg) => msg.text.startsWith(text)).length,
    // The callbacks the app's current instance released unfired.
    dropped: () => drops.get(app.instance).length,
  };
}
// --- A request in flight is taken over, not sent again ---
{
  const t = await start(fx(1));
  t.click('save');
  const r = await t.app.reload(fx(1));
  expect('in flight: not sent again', sentTo('POST /save'), 1);
  expect('in flight: reported as handed over', `${r.handedOver}|${r.ignored.length}|${r.unsent.length}`, '1|0|0');
  expect('in flight: the new app still waits for it', t.read('saving'), 'saving');
  await answer();
  expect('in flight: its answer reaches the new app', `${t.read('saving')}|${t.read('saved')}`, 'idle|quote from /save');
  // The answer is now part of the new app's session, so a further reload
  // replays it and has nothing to take over.
  const again = await t.app.reload(fx(1));
  expect('in flight: the answer is recorded by the new app', `${t.read('saved')}|${again.handedOver}|${sentTo('POST /save')}`, 'quote from /save|0|1');
  t.app.unmount();
}

// --- An answered request is replayed from the recording ---
{
  const t = await start(fx(1));
  t.click('load');
  await answer();
  await t.app.reload(fx(1));
  expect('answered: not sent again', sentTo('GET /load'), 1);
  expect('answered: the replay gets the recorded answer', t.read('loaded'), 'quote from /load');
  t.app.unmount();
}

// --- A timer in flight keeps going, and answers the new app ---
// Remind and Search wait 300 ms. Reloaded 200 ms in, each fires 100 ms after
// the reload, on the time the old app set, and once.
{
  const t = await start(fx(1));
  t.click('remind');
  t.type('search', 'joy');
  await pass(200);
  await t.app.reload(fx(1));
  await pass(99);
  expect('timer: not before its time', `${t.read('reminded')}|${t.read('searched')}`, '0|0');
  await pass(1);
  expect('timer: fires on the time it had left', t.read('reminded'), '1');
  expect('debounce: fires on the time it had left', t.read('searched'), '1');
  await pass(1000);
  expect('timer and debounce: each fires once', `${t.read('reminded')}|${t.read('searched')}`, '1|1');
  expect('timer and debounce: the new app records them', `${t.recorded('Reminded(')}|${t.recorded('Searched(')}`, '1|1');
  t.app.unmount();
}

// --- Replaying a debounce re-armed releases the callback it replaced ---
// As running it did in the old app: the replay holds the debounce back, so
// the runtime never gets to release it.
{
  const t = await start(fx(1));
  t.type('search', 'j');
  t.type('search', 'jo');
  t.type('search', 'joy');
  await t.app.reload(fx(1));
  expect('debounce replayed: the two replaced callbacks are released', t.dropped(), 2);
  await pass(300);
  expect('debounce replayed: the last one fires', `${t.read('searched')}|${t.dropped()}`, '1|2');
  t.app.unmount();
}

// --- A debounce taken over ends like one of the new app's own ---
// Typing again after the reload re-arms it, so the one the old app set never
// fires, and the callback the new app held for it is released, once.
{
  const t = await start(fx(1));
  t.type('search', 'joy');
  await pass(200);
  await t.app.reload(fx(1));
  const before = t.dropped();
  t.type('search', 'joys');
  await pass(100);
  expect('debounce re-armed: the one taken over never fires', t.read('searched'), '0');
  expect('debounce re-armed: its callback is released', t.dropped() - before, 1);
  await pass(200);
  expect('debounce re-armed: the new one fires', t.read('searched'), '1');
  await pass(1000);
  expect('debounce re-armed: once, releasing nothing more', `${t.read('searched')}|${t.dropped() - before}`, '1|1');
  t.app.unmount();
}
{
  const t = await start(fx(1));
  t.type('search', 'joy');
  await pass(200);
  await t.app.reload(fx(1));
  let before = t.dropped();
  t.click('stop-search');
  await pass(1000);
  expect('debounce canceled: the one taken over never fires', `${t.read('searched')}|${t.dropped() - before}`, '0|1');
  // Two reloads in a row: the second app takes it over from the first app's
  // successor, and ending it there still keeps the original from firing.
  t.type('search', 'joy');
  await pass(100);
  await t.app.reload(fx(1));
  await t.app.reload(fx(1));
  before = t.dropped();
  t.click('stop-search');
  await pass(1000);
  expect('debounce canceled after two reloads: never fires', `${t.read('searched')}|${t.dropped() - before}`, '0|1');
  t.app.unmount();
}

// --- A digest in flight answers the new app ---
{
  const subtle = globalThis.crypto.subtle;
  const digest = subtle.digest;
  const pending = [];
  subtle.digest = (algorithm, data) =>
    new Promise((resolve) => pending.push(() => resolve(createHash('sha256').update(new Uint8Array(data)).digest())));
  const t = await start(fx(1));
  t.click('hash');
  await t.app.reload(fx(1));
  expect('digest: not worked out again', pending.length, 1);
  for (const finish of pending.splice(0)) finish();
  await flush();
  subtle.digest = digest;
  expect('digest: arrives once, right', `${t.read('digest')}|${t.recorded('Hashed(')}`, `${createHash('sha256').update('joy').digest('hex')}|1`);
  t.app.unmount();
}

// --- A request the new code asks for, which the old app never sent ---
// v2's Bump also reports to /analytics. Replaying the session's Bumps must
// not send those reports now: by default the replay stops before the first
// Bump, while init's new request goes out as on a fresh page load.
{
  const t = await start(fx(1));
  t.click('bump');
  t.click('bump');
  t.click('save');
  await answer();
  const r = await t.app.reload(fx(2));
  expect('new request, stop: stops before the message asking for it',
    `${r.stopped?.reason}|${r.stopped?.request}|${r.stopped?.text}|${r.stopped?.dropped}`, 'request|POST /analytics|Bump|4');
  expect('new request, stop: sends nothing for the old session', sentTo('POST /analytics'), 0);
  expect('new request, stop: leaves the state from before it', `${t.read('bumps')}|${t.read('saved')}`, '0|');
  expect('new request, stop: init asks for /config once', sentTo('GET /config'), 1);
  await answer();
  expect('new request, stop: init gets its answer', t.read('config'), 'quote from /config');
  // From here on v2 runs as written, its own Bumps report.
  t.click('bump');
  expect('new request, stop: the app\'s own requests go out', sentTo('POST /analytics'), 1);
  t.app.unmount();
}
{
  const t = await start(fx(1));
  t.click('bump');
  t.click('bump');
  t.click('save');
  await answer();
  const r = await t.app.reload(fx(2), { replay: 'skip' });
  expect('new request, skip: replays everything', `${r.stopped}|${t.read('bumps')}|${t.read('saved')}`, 'null|2|quote from /save');
  expect('new request, skip: reports what it did not send', r.unsent.join(','), 'POST /analytics,POST /analytics');
  expect('new request, skip: sends nothing for the old session', sentTo('POST /analytics'), 0);
  t.app.unmount();
}

// --- Several reloads while one request is in flight ---
{
  const t = await start(fx(1));
  t.click('save');
  await t.app.reload(fx(1));
  await t.app.reload(fx(1));
  const r = await t.app.reload(fx(1));
  expect('reloads in a row: the last app took it over', `${r.handedOver}|${sentTo('POST /save')}`, '1|1');
  await answer();
  expect('reloads in a row: the answer arrives once', `${t.read('saved')}|${t.recorded('Saved(')}`, 'quote from /save|1');
  t.app.unmount();
}

// --- A request taken over that then fails ---
{
  const t = await start(fx(1));
  t.click('save');
  await t.app.reload(fx(1));
  await fail();
  expect('failed: the new app gets the failure', `${t.read('saving')}|${t.read('saved')}`, 'idle|failed');
  t.app.unmount();
}

// --- Two identical requests in flight ---
{
  const t = await start(fx(1));
  t.click('load');
  t.click('load');
  const r = await t.app.reload(fx(1));
  expect('identical: both taken over, none sent again', `${r.handedOver}|${sentTo('GET /load')}`, '2|2');
  await answer();
  expect('identical: each answer arrives once', t.read('loaded'), 'quote from /loadquote from /load');
  t.app.unmount();
}

// --- Requests that differ only in their headers ---
// Greet sends the same request to /greet but for its Accept-Language header.
// In v2, English no longer sends one, so pairing by method, URL and body
// alone would hand English's answer to the Swedish request.
{
  const t = await start(fx(1));
  t.click('greet-en');
  t.click('greet-sv');
  const r = await t.app.reload(fx(2));
  expect('headers: only the request with the same headers is taken over',
    `${r.handedOver}|${r.ignored.join(',')}|${r.stopped}|${sentTo('GET /greet')}`, '1|GET /greet|null|2');
  await answer();
  expect('headers: each answer goes to its own request', t.read('greeted'), 'sv: hello in sv;');
  t.app.unmount();
}
// v2 has German accept de-DE where v1 accepted de: a request the edit
// changed, so the old one's answer is not taken, and replaying would send
// the new one.
{
  const t = await start(fx(1));
  t.click('greet-de');
  const r = await t.app.reload(fx(2));
  expect('headers: a request whose headers changed is not taken over',
    `${r.handedOver}|${r.ignored.join(',')}|${r.stopped?.reason}|${r.stopped?.text}`, '0|GET /greet|request|Greet("de")');
  expect('headers: and is not sent again', sentTo('GET /greet'), 1);
  await answer();
  expect('headers: its answer is ignored', t.read('greeted'), '');
  t.app.unmount();
}

// --- A crashed app's request in flight answers the fixed build ---
// hot_v4.roc crashes on Remove, hot_v3.roc is the fix (see check_hot.mjs).
{
  const t = await start(readFileSync(hotWasmPath('hot_v4')));
  t.type('draft', 'pear');
  t.click('add');
  t.click('fetch');
  let crashed = false;
  try {
    t.el('items').children[0].listeners.click();
  } catch {
    crashed = true;
  }
  expect('crashed: the old app crashed with a request in flight', `${crashed}|${sentTo('GET /quote')}`, 'true|1');
  const r = await t.app.reload(readFileSync(hotWasmPath('hot_v3')));
  expect('crashed: the fixed build takes the request over', `${r.handedOver}|${sentTo('GET /quote')}|${t.read('quote')}`, '1|1|loading');
  await answer();
  expect('crashed: its answer reaches the fixed build', t.read('quote'), 'quote from /quote');
  t.app.unmount();
}

// --- Messages too long to keep whole ---
// A message is known by a hash of its whole text and kept with the start of
// it, so the session stays small however long messages get.
{
  const t = await start(fx(1));
  body.set('/load', new TextEncoder().encode('{"homes":' + '7'.repeat(100_000) + '}'));
  t.click('load');
  await answer();
  body.delete('/load');
  const entry = hot.session(t.app).find((e) => e.op === 'dispatchBytes');
  const kept = entry.msgs[0].text;
  expect('long: the message keeps only the start of its text', kept.length <= 161 && kept.endsWith('…'), true);
  expect('long: the input is kept whole, to replay', entry.inputs[0].length > 100_010, true);
  await t.app.reload(fx(1));
  expect('long: the replay still knows it', `${t.read('loaded')}|${sentTo('GET /load')}`, '{"homes":7777777|1');
  t.app.unmount();
}
// Pick A and Pick B differ only past the start kept for showing. v2 swaps the
// buttons, so the one at the recorded position sends the other message,
// which only the whole text tells apart.
{
  const t = await start(fx(1));
  t.click('pick-b');
  await t.app.reload(fx(2), { replay: 'skip' });
  expect('long: told apart by the whole text', t.read('picked'), 'B');
  t.app.unmount();
}
// Label's function prints past the start kept for showing, and still makes
// the message ambiguous: the reload reads the button's signature for it.
{
  const textReads = countTextReads();
  const t = await start(fx(1));
  t.click('label');
  expect('long: ambiguous past the start kept', textReads.reads, 1);
  await t.app.reload(fx(1));
  expect('long: the ambiguous message replays', t.read('labeled'), '1');
  t.app.unmount();
}

// --- A build without hot reload restarts, and its request in flight is ignored ---
{
  const t = await start(readFileSync(plainWasmPath('hot_fx_v1')));
  t.click('save');
  const r = await t.app.reload(readFileSync(plainWasmPath('hot_fx_v1')));
  expect('restart: reported', `${r.restarted}|${r.ignored.join(',')}|${sentTo('POST /save')}`, 'true|POST /save|1');
  await answer();
  expect('restart: the answer is ignored', `${t.read('saving')}|${t.read('saved')}`, 'idle|');
  t.app.unmount();
}

// --- Reloads that fail leave the running app as it was ---
{
  const t = await start(fx(1));
  t.click('bump');
  const garbage = await t.app.reload(new Uint8Array([0, 1, 2, 3])).then(() => 'resolved', (err) => err.constructor.name);
  expect('error: a module that does not compile is refused', garbage, 'CompileError');
  t.click('save');
  const init = await t.app.reload(readFileSync(hotWasmPath('hot_init_crash'))).then(() => 'resolved', () => 'rejected');
  expect('error: a module whose init crashes is refused', init, 'rejected');
  t.click('bump');
  expect('error: the running app goes on', t.read('bumps'), '2');
  await answer();
  expect('error: its request in flight is still its own', t.read('saved'), 'quote from /save');
  // It recorded all the while, so a good reload replays all of it.
  const r = await t.app.reload(fx(1));
  expect('error: a good reload afterwards replays it all', `${r.replayed}|${t.read('bumps')}|${t.read('saved')}`, '4|2|quote from /save');
  t.app.unmount();
  const unmounted = await t.app.reload(fx(1)).then(() => 'resolved', (err) => err.message);
  expect('error: an unmounted app does not reload', unmounted, 'reload: the app was unmounted');
}

// --- A runtime this module does not fully know is not hot reloaded ---
// Rather than guess what becomes of an op it has no description
// of, the dev module says so and leaves the app alone, which a rebuild then
// reloads the page for.
for (const [what, name, extend] of [
  ['op', 'dispatchTeleport', (hooks) => { hooks.ops.dispatchTeleport = () => {}; }],
]) {
  const { exports } = await instantiate(new WebAssembly.Module(fx(1)), { env: {} });
  const rt = makeRuntime(exports, fakeDom, new El('#root'));
  extend(rt.hooks);
  const errors = [];
  const consoleError = console.error;
  console.error = (...args) => errors.push(args.join(' '));
  const app = {};
  try {
    hot.adopt(app, { runtime: () => rt });
  } finally {
    console.error = consoleError;
  }
  expect(`unknown ${what}: says so, naming it`, errors.length === 1 && errors[0].includes(name), true);
  expect(`unknown ${what}: the app is not hot reloaded`, `${app.reload}|${hot.apps.has(app)}`, 'undefined|false');
}

// --- A hot build stays import-free, like any other ---
for (const name of ['hot_v1', 'hot_fn_v1', 'hot_fx_v1', 'hot_init_crash']) {
  const imports = WebAssembly.Module.imports(new WebAssembly.Module(readFileSync(hotWasmPath(name))));
  expect(`${name} imports nothing`, imports.length, 0);
}

mock.timers.reset();
