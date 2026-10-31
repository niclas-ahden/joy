// Node harness for what stays with a page through a hot reload (www/hot-seams.js):
// the handle mount returned reaches the rebuilt app, which takes over the outgoing
// ports, picked files and control state of the one it replaces. Also what
// the seams change in a browser and a fake DOM cannot reach: how a rebuilt module
// is fetched, and the visibility observer.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_handle.mjs
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const { browserDom, mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, FakeFile, fakeDom } from './fakedom.mjs';
import { expect, hotWasmPath } from './harness.mjs';

const build = readFileSync(hotWasmPath('hot_handle'));
// Digests resolve on the crypto threadpool, so ask until the answer shows, or give up.
const until = async (ready) => {
  for (let i = 0; i < 400 && !ready(); i++) await new Promise((resolve) => setTimeout(resolve, 5));
};

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};

async function start() {
  const root = new El('#root');
  const app = await mount({ wasm: build, root, flags: '', dom: fakeDom });
  const el = (id) => byId(root, id);
  return { app, el, read: (id) => el(id).textContent };
}

// The handler id the current runtime gave an element's event, which is what a
// page passes to app.dispatch. A kept element also holds its predecessors' maps,
// so the newest is the last.
const handlerOf = (node, event) => {
  const maps = Object.getOwnPropertySymbols(node).filter((s) => s.description === 'joyEvents');
  return node[maps.at(-1)].get(event).id;
};

// --- What a page sends through the handle is recorded, and reaches the rebuilt app ---
{
  const t = await start();
  t.app.dispatch(handlerOf(t.el('bump'), 'click'));
  t.app.dispatchValue(handlerOf(t.el('field'), 'input'), 'joy');
  const first = await t.app.reload(build);
  expect('handle: what it sent is replayed', `${first.replayed}|${first.stopped}`, '2|null');
  expect('handle: the state came through', `${t.read('count')}|${t.read('typed')}`, '1|joy');

  t.app.dispatch(handlerOf(t.el('bump'), 'click'));
  t.app.dispatchValue(handlerOf(t.el('field'), 'input'), 'joy!');
  expect('handle: reaches the rebuilt app', `${t.read('count')}|${t.read('typed')}`, '2|joy!');
  const second = await t.app.reload(build);
  expect('handle: what the rebuilt app got is recorded too', `${second.replayed}|${t.read('count')}|${t.read('typed')}`, '4|2|joy!');

  t.app.sendPort('ping', '');
  expect('handle: a port reaches the rebuilt app', t.read('count'), '3');
  t.app.unmount();
}

// --- Unmounting stops the app that runs now ---
{
  const t = await start();
  await t.app.reload(build);
  t.app.sendPort('ping', '');
  expect('unmount: the rebuilt app hears a port before it', t.read('count'), '1');
  t.app.unmount();
  t.app.sendPort('ping', '');
  expect('unmount: and not after it', t.read('count'), '1');
}

// --- An outgoing port handler stays ---
{
  const t = await start();
  const said = [];
  t.app.onPort('said', (value) => said.push(value));
  await t.app.reload(build);
  t.el('say').listeners.click();
  expect('port: the handler the page set hears the rebuilt app', said.join(','), '0');
  t.app.unmount();
}

// --- A picked file stays readable ---
{
  const t = await start();
  const upload = t.el('upload');
  upload.fakeFile = new FakeFile('notes.txt', 'hi');
  upload.listeners.change({ target: upload });
  await t.app.reload(build);
  const hashStart = (text) => String(createHash('sha256').update(text).digest()[0]);
  const hash = async () => {
    t.el('hash').listeners.click();
    await until(() => t.read('hash-start') !== '0');
    return t.read('hash-start');
  };
  expect('file: the rebuilt app reads what the old one was given', await hash(), hashStart('hi'));

  // The app keeps hashing the first file, which a second with its id would replace.
  upload.fakeFile = new FakeFile('other.txt', 'yo');
  upload.listeners.change({ target: upload });
  expect('file: one picked after the reload has an id of its own', await hash(), hashStart('hi'));
  t.app.unmount();
}

// --- What the old app's features set up is cleaned up when the rebuilt one unmounts ---
// A module of its own, as a feature sets up its cleanup once per module.
{
  const { mount: mountFresh } = await import(`../build/${process.env.JOY_OPT}/runtime.js?unmount`);
  const fx = readFileSync(hotWasmPath('hot_fx_v1'));
  const root = new El('#root');
  const app = await mountFresh({ wasm: fx, root, flags: '', dom: fakeDom });
  byId(root, 'search').listeners.input({ target: { value: 'joy' } });
  await app.reload(fx);
  const realClear = globalThis.clearTimeout;
  let cleared = 0;
  globalThis.clearTimeout = (handle) => {
    cleared += 1;
    realClear(handle);
  };
  app.unmount();
  globalThis.clearTimeout = realClear;
  expect('unmount: the pending debounce the old app set is cleared', cleared, 1);
}

// --- The perf counters the page holds go on counting ---
{
  const t = await start();
  t.app.perf.enabled = true;
  await t.app.reload(build);
  const before = t.app.perf.entries;
  t.el('bump').listeners.click();
  expect('perf: counts what the rebuilt app does', t.app.perf.entries, before + 1);
  t.app.unmount();
}

// --- A control the view declares is still pinned to it ---
{
  const t = await start();
  await t.app.reload(build);
  const box = t.el('agree');
  box.checked = true;
  box.listeners.change({ target: box, type: 'change' });
  expect('control: the rebuilt app pins what the old app rendered', box.checked, false);
  t.app.unmount();
}

// --- A rebuilt module is never the one the browser cached ---
{
  const t = await start();
  const realFetch = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, opts) => {
    asked.push({ url, opts });
    return url.includes('gone')
      ? { ok: false, status: 404, statusText: 'Not Found', headers: new Headers() }
      : { ok: true, status: 200, headers: new Headers(), arrayBuffer: async () => build.buffer.slice(build.byteOffset, build.byteOffset + build.byteLength) };
  };
  await t.app.reload('/bundle/app.wasm');
  expect('fetch: of the module asked for', asked.at(-1).url, '/bundle/app.wasm');
  expect('fetch: past the cache', asked.at(-1).opts?.cache, 'no-store');
  const failed = await t.app.reload('/gone/app.wasm').then(() => 'loaded', (err) => err.message);
  expect('fetch: says what it could not get', failed.includes('could not fetch /gone/app.wasm (404'), true);
  globalThis.fetch = realFetch;
  t.app.unmount();
}

// --- The browser's observer leaves out a report the old app already had ---
{
  const observers = [];
  globalThis.IntersectionObserver = class {
    constructor(report, options) {
      Object.assign(this, { report, options, active: true });
      observers.push(this);
    }
    observe(node) { this.node = node; }
    disconnect() { this.active = false; }
  };
  const node = new El('div');
  const watch = (seen) => {
    const fired = { count: 0 };
    fired.stop = browserDom.observeVisibility(node, '10px', () => { fired.count += 1; }, seen);
    fired.observer = observers.at(-1);
    fired.report = (isIntersecting) => fired.observer.report([{ isIntersecting }]);
    return fired;
  };

  const told = watch(true);
  expect('observer: watches the node with the margin', `${told.observer.node === node}|${told.observer.options.rootMargin}`, 'true|10px');
  told.report(true);
  expect('observer: leaves out the first report when told', told.count, 0);
  told.report(true);
  expect('observer: and only that one', told.count, 1);
  told.stop();
  expect('observer: stops', told.observer.active, false);

  const outside = watch(true);
  outside.report(false);
  outside.report(true);
  expect('observer: a node out of view has nothing left out', outside.count, 1);

  const fresh = watch(undefined);
  fresh.report(true);
  expect('observer: a new one reports the first time', fresh.count, 1);
  delete globalThis.IntersectionObserver;
}
