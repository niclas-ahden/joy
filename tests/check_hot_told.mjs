// Node harness for what a hot reload does with what an app tells the world
// outside itself (see `hold`, `handover` and goLive in www/hot.js).
//
// - After a page reload the page's own JavaScript has started over, so it
//   hears every port message again, in order, and the last focus and scroll
//   are done again. A reload in place tells nobody anything twice.
// - The URL after a page reload is the one the app was at, which Back may
//   have reached, not the last one it pushed.
// - A call the old app had its answer to is done. When that answer no longer
//   replays, the call is not made a second time.
// - A session belongs to the URL it was saved on.
//
// tests/apps/hot_told_v1.roc and hot_told_v2.roc, built by tests.roc with
// JOY_HOT. Run from the repo root: JOY_OPT=speed node tests/check_hot_told.mjs
import { readFileSync } from 'node:fs';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, fakeDom, fakeLocation, focusCalls, popstate, scrolls } from './fakedom.mjs';
import { expect, hotWasmPath } from './harness.mjs';

const told = (n) => readFileSync(hotWasmPath(`hot_told_v${n}`));
const flush = () => new Promise((resolve) => setImmediate(resolve));
// Compression and the replay's own waiting take turns of the event loop.
const settle = async () => { for (let i = 0; i < 20; i++) await flush(); };

// sessionStorage as a browser has it, which node does not.
const stored = new Map();
globalThis.sessionStorage = {
  getItem: (key) => stored.get(key) ?? null,
  setItem: (key, value) => stored.set(key, value),
  removeItem: (key) => stored.delete(key),
};

// The clipboard, which takes every write.
const written = [];
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: { clipboard: { writeText: async (text) => { written.push(text); } } },
});

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};
const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

// Mount a build on a page whose own JavaScript listens to the `page` port.
async function start(wasm) {
  const heard = [];
  const root = new El('#root');
  const app = await mount({ wasm, root, flags: '', dom: fakeDom, setup: (a) => a.onPort('page', (value) => heard.push(value)) });
  await settle();
  return { app, heard, state: () => textOf(byId(root, 'state')), click: (id) => byId(root, id).listeners.click() };
}

// --- A page reload: the page's JavaScript hears it all again ---
{
  const t = await start(told(1));
  t.click('tell');
  t.click('tell');
  t.click('focus');
  t.click('scroll');
  t.click('tell');
  t.click('go-a');
  t.click('go-b');
  popstate('/a');
  expect('page: the session as it was lived', `${t.state()}|${t.heard.join(', ')}|${fakeLocation.url}`, 'told 3 at /a copied 0|boot, note 0, note 1, note 2|/a');

  // What a page does on its way out and back in.
  await globalThis.__JOY_HOT__.saveSessions();
  await settle();
  t.app.unmount();
  focusCalls.length = 0;
  scrolls.length = 0;
  fakeLocation.url = '/';

  const back = await start(told(1));
  expect('page: the app is where it was', back.state(), 'told 3 at /a copied 0');
  expect('page: the new page hears every port message, once, in order', back.heard.join(', '), 'boot, note 0, note 1, note 2');
  expect('page: the last focus is done again', focusCalls.join(', '), '#field');
  expect('page: and the last scroll', scrolls.map((to) => `${to.x},${to.y}`).join(' '), '0,42');
  expect('page: the URL is the one Back had reached', fakeLocation.url, '/a');
  back.app.unmount();
}

// --- A reload in place: nobody hears anything twice ---
{
  focusCalls.length = 0;
  const t = await start(told(1));
  t.click('tell');
  t.click('focus');
  const report = await t.app.reload(told(1));
  expect('place: the messages replayed', `${report.replayed}|${t.state()}`, '2|told 1 at / copied 0');
  expect('place: the page heard each port message once', t.heard.join(', '), 'boot, note 0');
  expect('place: and the focus was not moved again', focusCalls.length, 1);
  t.app.unmount();
}

// --- A call the old app had its answer to is not made again ---
for (const replay of ['skip', 'stop']) {
  written.length = 0;
  const t = await start(told(1));
  t.click('tell');
  t.click('copy');
  await settle();
  expect(`${replay}: the clipboard was written and the app was told`, `${written.length}|${t.state()}`, '1|told 1 at / copied 1');
  // v2 names the answer's message another way, so v1's answer finds no
  // source in it, while v2's replay asks for the write again.
  const report = await t.app.reload(told(2), { replay });
  await settle();
  expect(`${replay}: the answer did not replay`, replay === 'skip' ? report.skipped.length : report.stopped?.reason, replay === 'skip' ? 1 : 'gone');
  expect(`${replay}: the clipboard was not written a second time`, written.length, 1);
  t.click('copy');
  await settle();
  expect(`${replay}: a new write works, and its answer arrives`, `${written.length}|${t.state()}`, '2|told 1 at / copied 1');
  t.app.unmount();
}

// --- A session belongs to the URL it was saved on ---
{
  // Each page is its own copy of the dev module, which notes the URL it
  // loaded at.
  globalThis.location = { href: 'http://site.test/one' };
  await import('../www/hot.js?page=one');
  const one = await start(told(1));
  one.click('tell');
  await globalThis.__JOY_HOT__.saveSessions();
  await settle();
  one.app.unmount();
  expect('url: the session was saved', stored.size, 1);

  globalThis.location = { href: 'http://site.test/two' };
  await import('../www/hot.js?page=two');
  const two = await start(told(1));
  expect('url: another page with the same bundle starts fresh', two.state(), 'told 0 at / copied 0');
  expect('url: and the session is not left for a later page', stored.size, 0);
  two.app.unmount();
}
