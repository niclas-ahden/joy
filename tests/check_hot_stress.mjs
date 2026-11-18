// Node harness for long sessions: what a hot reload costs once an app has
// run for a while (see catchUp in www/hot.js). The budgets are on work, which
// is the same on every machine: how often the view is written, how much the
// rebuilt app's memory holds, how much a saved session takes of what a
// browser's sessionStorage holds. Each reload also has a ceiling on its time,
// set many times above what it takes, which only something that grows with
// the square of the session would reach.
//
// tests/apps/rows.roc keeps a model of one size however long it runs, so
// what grows here is the session alone.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_stress.mjs
import { readFileSync } from 'node:fs';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, byId } from './fakedom.mjs';
import { countingDom, expect, expectAtMost, hotWasmPath } from './harness.mjs';

const hot = globalThis.__JOY_HOT__;
const rows = readFileSync(hotWasmPath('rows'));

// The clock ticks when a check says so.
const intervals = [];
globalThis.setInterval = (fn) => { intervals.push(fn); return intervals.length; };
globalThis.clearInterval = () => {};

// sessionStorage as a browser has it, which node does not.
const stored = new Map();
globalThis.sessionStorage = {
  getItem: (key) => stored.get(key) ?? null,
  setItem: (key, value) => stored.set(key, value),
  removeItem: (key) => stored.delete(key),
};
// What one sessionStorage value holds in Chromium, Firefox and WebKit.
const STORAGE_HOLDS = 5_240_000;

const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

async function start(flags) {
  const root = new El('#root');
  const counted = countingDom();
  const app = await mount({ wasm: rows, root, flags, dom: counted.dom });
  const read = (id) => textOf(byId(root, id));
  const click = (...ids) => {
    const ev = { bubbles: true, stopped: false, stopPropagation() { this.stopped = true; } };
    for (const node of ids.map((id) => byId(root, id))) {
      if (ev.stopped) break;
      node.listeners.click?.(ev);
    }
  };
  const tick = intervals.at(-1);
  // Reload into the same build, timed, with what it wrote into the view.
  const reload = async () => {
    const before = { ...counted.counts };
    const t0 = performance.now();
    const report = await app.reload(rows);
    return {
      report,
      ms: performance.now() - t0,
      textWrites: counted.counts.textWrites - before.textWrites,
      memory: app.instance.exports.memory.buffer.byteLength,
    };
  };
  return { app, read, click, tick, reload };
}

// The characters the page's sessions take in sessionStorage. They are taken
// out again, or the next app mounted here would pick the session up, as an
// app does after its page reloaded.
async function savedSize() {
  await hot.saveSessions();
  for (let i = 0; i < 20; i++) await new Promise((resolve) => setImmediate(resolve));
  const size = [...stored.values()].reduce((n, value) => n + value.length, 0);
  stored.clear();
  return size;
}

// --- Messages that need no view: a clock that ticked 50,000 times ---
{
  const t = await start('');
  for (let i = 0; i < 50_000; i++) t.tick();
  expect('ticks: the clock ran', t.read('ticks'), '50000');
  const saved = await savedSize();
  const r = await t.reload();
  expect('ticks: every one replays', `${r.report.replayed}|${r.report.skipped.length}|${t.read('ticks')}`, '50000|0|50000');
  expectAtMost('ticks: the view is written a few times, not once a tick', r.textWrites, 20);
  expectAtMost('ticks: the rebuilt app holds a model of the same size (bytes)', r.memory, 8 * 1024 * 1024);
  expectAtMost('ticks: the saved session is a small part of what sessionStorage holds', saved, STORAGE_HOLDS / 20);
  expectAtMost('ticks: the reload takes no time to speak of (ms)', r.ms, 3_000);
  t.app.unmount();
}

// --- Messages from the view: 20,000 clicks on a small page ---
{
  const t = await start('');
  for (let i = 0; i < 20_000; i++) t.click('plain-alpha');
  const before = t.read('log');
  const saved = await savedSize();
  const r = await t.reload();
  expect('clicks: every one replays', `${r.report.replayed}|${r.report.skipped.length}`, '20000|0');
  expect('clicks: the app is where it was', t.read('log'), before);
  expectAtMost('clicks: the rebuilt app holds a model of the same size (bytes)', r.memory, 8 * 1024 * 1024);
  expectAtMost('clicks: the saved session is a small part of what sessionStorage holds', saved, STORAGE_HOLDS / 20);
  expectAtMost('clicks: the reload takes about as long as the clicks did (ms)', r.ms, 10_000);
  t.app.unmount();
}

// --- Handlers that ran together: 5,000 clicks that each passed two ---
{
  const t = await start('');
  for (let i = 0; i < 5_000; i++) t.click('flip', 'outer');
  const before = t.read('log');
  expect('together: the last click was heard by both', before.endsWith('flipped, saw flipped'), true);
  const r = await t.reload();
  expect('together: every message replays', `${r.report.replayed}|${r.report.skipped.length}`, '10000|0');
  expect('together: the app is where it was', t.read('log'), before);
  expectAtMost('together: the reload takes about as long as the clicks did (ms)', r.ms, 10_000);
  t.app.unmount();
}

// --- A page of some size: 2,000 clicks on 600 rows ---
{
  const t = await start('300');
  for (let i = 0; i < 2_000; i++) t.click(i % 2 === 0 ? 'plain-row7' : 'keyed-row250');
  const before = t.read('log');
  const r = await t.reload();
  expect('rows: every click replays', `${r.report.replayed}|${r.report.skipped.length}`, '2000|0');
  expect('rows: the app is where it was', t.read('log'), before);
  expectAtMost('rows: the rebuilt app holds a model of the same size (bytes)', r.memory, 16 * 1024 * 1024);
  expectAtMost('rows: the reload takes about as long as the clicks did (ms)', r.ms, 20_000);
  t.app.unmount();
}

// --- A whole app, used the way one is: TodoMVC with 150 todos ---
// Fewer messages, of every kind the app has, and a view that changes shape:
// rows come and go, some are edited in place, some are ticked off.
{
  const { byClass, byClassAll, byRole, byRoleAll, find, html } = await import('./fakedom.mjs');
  const todomvc = readFileSync(hotWasmPath('spa-todomvc'));
  const root = new El('#root');
  const app = await mount({ wasm: todomvc, root, flags: '', dom: countingDom().dom });
  const newTodo = () => byRole(root, 'textbox', 'What needs to be done?');
  const add = (title) => {
    newTodo().listeners.input({ target: { value: title } });
    newTodo().listeners.keydown({ key: 'Enter', preventDefault: () => {} });
  };
  const rows = () => byRoleAll(byClass(root, 'todo-list') ?? root, 'listitem');
  for (let i = 1; i <= 150; i++) add(`todo number ${i}`);
  // Tick every third off, through its checkbox's change event.
  for (let i = 0; i < 150; i += 3) {
    const toggle = byClassAll(root, 'toggle')[i];
    toggle.checked = true;
    toggle.listeners.change({ target: toggle });
  }
  // Take every tenth of what is there off the list, last first.
  for (let i = 140; i >= 0; i -= 10) byClassAll(root, 'destroy')[i].listeners.click();
  find(root, 'Clear completed').listeners.click();
  // Edit the first that is left: a double click on its label, a new title,
  // Enter.
  find(root, 'todo number 2').listeners.dblclick({});
  byClassAll(rows()[0], 'edit')[0].listeners.input({ target: { value: 'todo number 2, edited' } });
  byClassAll(rows()[0], 'edit')[0].listeners.keydown({ key: 'Enter', preventDefault: () => {} });
  for (let i = 151; i <= 170; i++) add(`todo number ${i}`);
  const before = html(root);
  expect('todomvc: the list is as long as it should be', `${rows().length}|${find(root, 'todo number 2, edited') !== null}`, '110|true');

  const t0 = performance.now();
  const report = await app.reload(todomvc);
  const ms = performance.now() - t0;
  expect('todomvc: nothing was skipped', `${report.skipped.length}|${report.stopped ?? 'ran to the end'}`, '0|ran to the end');
  expect('todomvc: the page is the one it was, element for element', html(root) === before, true);
  expectAtMost('todomvc: the rebuilt app holds a model of the same size (bytes)', app.instance.exports.memory.buffer.byteLength, 16 * 1024 * 1024);
  expectAtMost('todomvc: the reload takes about as long as the session did (ms)', ms, 20_000);
  add('one more');
  expect('todomvc: and the app goes on', rows().length, 111);
  app.unmount();
}

// --- A large view and few messages: a table of 10,000 rows ---
// Each message here builds or changes thousands of elements, so the cost is
// in the views a replay passes through, not in how many messages there are.
{
  const { html } = await import('./fakedom.mjs');
  const table = readFileSync(hotWasmPath('jsbench_keyed'));
  const root = new El('#root');
  const app = await mount({ wasm: table, root, flags: '', dom: countingDom().dom });
  const press = (id) => byId(root, id).listeners.click();
  const tbody = () => byId(root, 'tbody');
  const select = (i) => tbody().children[i].children[1].children[0].listeners.click();
  const remove = (i) => tbody().children[i].children[2].children[0].listeners.click();
  press('run');
  press('update');
  press('swaprows');
  select(500);
  remove(3);
  press('add');
  press('runlots');
  select(7_000);
  remove(9_998);
  press('update');
  press('swaprows');
  expect('table: ten thousand rows less one', tbody().children.length, 9_999);
  const before = html(root);

  const t0 = performance.now();
  const report = await app.reload(table);
  const ms = performance.now() - t0;
  expect('table: every message replays', `${report.replayed}|${report.skipped.length}`, '11|0');
  expect('table: the page is the one it was, element for element', html(root) === before, true);
  expectAtMost('table: the rebuilt app holds what one such table takes (bytes)', app.instance.exports.memory.buffer.byteLength, 96 * 1024 * 1024);
  expectAtMost('table: the reload takes about as long as the session did (ms)', ms, 30_000);
  remove(0);
  expect('table: and the app goes on', tbody().children.length, 9_998);
  app.unmount();
}
