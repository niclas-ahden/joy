// Node harness for apps sharing a page, which run one copy of the feature code:
// what a feature keeps for one app does not reach another, stays through a hot
// reload, and goes when the app is unmounted. The same debounce key and the same
// file id mean different things in different apps.
// Run from the repo root: JOY_OPT=speed node tests/check_many_apps.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { El, FakeFile, fakeDom } from './fakedom.mjs';
import { appRuntime, expect, hotWasmPath, wasmPath } from './harness.mjs';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const until = async (ready) => {
  for (let i = 0; i < 400 && !ready(); i++) await sleep(5);
};

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};

// Object URLs that name their file, and which ones were made and revoked.
let made = 0;
const revoked = [];
URL.createObjectURL = (file) => `blob:${file.name}#${++made}`;
URL.revokeObjectURL = (url) => { revoked.push(url); };

// The app's debounce timers: the fixture arms them for 80 ms.
const armed = [];
const cleared = new Set();
const realSetTimeout = globalThis.setTimeout;
const realClearTimeout = globalThis.clearTimeout;
globalThis.setTimeout = (fn, ms, ...rest) => {
  const handle = realSetTimeout(fn, ms, ...rest);
  if (ms === 80) armed.push(handle);
  return handle;
};
globalThis.clearTimeout = (handle) => {
  cleared.add(handle);
  realClearTimeout(handle);
};

async function start(mount, wasm) {
  const root = new El('#root');
  const app = await mount({ wasm, root, flags: '', dom: fakeDom });
  const el = (id) => byId(root, id);
  const read = (id) => el(id).textContent;
  return {
    app,
    read,
    click: (id) => el(id).listeners.click(),
    pick: (name) => {
      el('upload').fakeFile = new FakeFile(name, name);
      el('upload').listeners.change({ target: el('upload') });
    },
    ask: async () => {
      const before = read('url');
      el('ask').listeners.click();
      await until(() => read('url') !== before);
      return read('url');
    },
  };
}

const { mount } = await appRuntime('many_apps');
const wasm = readFileSync(wasmPath('many_apps'));
const pair = async () => [await start(mount, wasm), await start(mount, wasm)];

// --- Debounces ---
{
  const [a, b] = await pair();
  a.click('arm');
  b.click('arm');
  await sleep(160);
  expect('debounce: two apps can use one key', `${a.read('fired')}|${b.read('fired')}`, '1|1');

  a.click('arm');
  b.click('arm');
  a.click('cancel');
  await sleep(160);
  expect('debounce: a cancel reaches its own app', `${a.read('fired')}|${b.read('fired')}`, '1|2');

  a.click('arm');
  b.click('arm');
  a.app.unmount();
  await sleep(160);
  expect('debounce: unmounting an app leaves the other one waiting', b.read('fired'), '3');
  b.app.unmount();
}
{
  const [a, b] = await pair();
  a.click('arm');
  b.click('arm');
  const [ofA, ofB] = armed.slice(-2);
  b.app.unmount();
  expect('debounce: the app armed second clears its own on unmount', cleared.has(ofB), true);
  expect('debounce: and not the other one', cleared.has(ofA), false);
  a.app.unmount();
  expect('debounce: the app armed first clears its own on unmount', cleared.has(ofA), true);
}

// --- Object URLs ---
{
  const [a, b] = await pair();
  a.pick('a.mp3');
  b.pick('b.mp3');
  const ofA = await a.ask();
  const ofB = await b.ask();
  expect('object URL: an app gets a URL of its own file', ofA.startsWith('blob:a.mp3'), true);
  expect('object URL: and so does an app with the same file id', ofB.startsWith('blob:b.mp3'), true);

  const count = made;
  a.pick('c.mp3');
  await a.ask();
  a.click('ask');
  await sleep(20);
  expect('object URL: the same file keeps its URL', made, count + 1);

  revoked.length = 0;
  a.app.unmount();
  expect('object URL: unmounting lets go of the app\'s URLs', revoked.length, 2);
  expect('object URL: and of no other app\'s', revoked.includes(ofB), false);

  const again = await start(mount, wasm);
  again.pick('d.mp3');
  expect('object URL: a later app does not get an earlier one\'s', (await again.ask()).startsWith('blob:d.mp3'), true);
  again.app.unmount();
  b.app.unmount();
}

// --- A hot reload keeps what features hold, and each app keeps its own ---
{
  const { mount: hotMount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
  await import('../www/hot.js');
  const build = readFileSync(hotWasmPath('many_apps'));
  const hotPair = async () => [await start(hotMount, build), await start(hotMount, build)];

  const [a, b] = await hotPair();
  a.pick('a.mp3');
  const url = await a.ask();
  const count = made;
  await a.app.reload(build);
  expect('hot: the same file keeps its URL', `${a.read('url')}|${made}`, `${url}|${count}`);
  a.click('ask');
  await sleep(20);
  expect('hot: and the rebuilt app asks for the same one', `${a.read('url')}|${made}`, `${url}|${count}`);

  a.click('arm');
  b.click('arm');
  await a.app.reload(build);
  await sleep(160);
  expect('hot: pending debounces fire once, in the reloaded app and the other', `${a.read('fired')}|${b.read('fired')}`, '1|1');

  a.click('arm');
  await a.app.reload(build);
  a.click('cancel');
  await sleep(160);
  expect('hot: the rebuilt app cancels what the one before it armed', a.read('fired'), '1');

  a.click('arm');
  await a.app.reload(build);
  revoked.length = 0;
  a.app.unmount();
  expect('hot: unmounting the rebuilt app clears what it took over', `${cleared.has(armed.at(-1))}|${revoked.join()}`, `true|${url}`);
  b.app.unmount();
}

// --- State at the top of a feature file is shared by every app on the page ---
// The digest queue is the exception: it limits what the whole page holds in memory.
{
  const shared = new Set(['digestQueue', 'digestsRunning']);
  const found = [];
  for (const name of readdirSync('www/features')) {
    for (const line of readFileSync(`www/features/${name}`, 'utf8').split('\n')) {
      const hit = /^(?:let|var)\s+(\w+)/.exec(line) ?? /^const\s+(\w+)\s*=\s*(?:new\s|\[|\{)/.exec(line);
      if (hit && !shared.has(hit[1])) found.push(`${name}: ${hit[1]}`);
    }
  }
  expect('features: no state at the top of a file, use host.own', found.join(', '), '');
}
