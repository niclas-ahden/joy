// Node harness for examples/pages: one URL per page, the model holds only
// the page on screen, and links (full page loads) move between pages. Each
// mount here is one such page load: the path arrives as the flags and picks
// the page whose init runs. Checks that the path routes to the right page
// in both serving modes, that only that page's effects and subscriptions
// exist, that the links are relative and mark the current page, and that
// a message for a page that is not on screen is dropped.
// Run from the repo root: node tests/check_pages.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, byId, byRole, byRoleAll, fakeDom, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

// Captured timers (the clock's boot Effect uses setTimeout, its tick Sub
// setInterval). Every firing reads Date.now(), stubbed so the clock text is
// predictable.
const timeouts = [];
const intervals = [];
let cleared = 0;
let now = 0;
globalThis.Date.now = () => now;
globalThis.setTimeout = (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; };
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = () => { cleared += 1; };

const wasm = readFileSync(wasmPath('pages'));
const load = async (path) => {
  const root = new El('#root');
  await mount({ wasm, root, flags: path, dom: fakeDom });
  return root;
};
const textOf = (root, id) => htmlBare(byId(root, id)).replace(/<[^>]+>/g, '');
const links = (root) => byRoleAll(byId(root, 'pages'), 'link').map((a) => [a.attrs.get('href'), a.attrs.get('class') ?? ''].join(' ').trim()).join(', ');

// --- The root and unknown paths land on the counter, with no timers ---

let root = await load('/');
expect('root shows the counter', byId(root, 'counter') !== null, true);
expect('links are relative and mark the current page', links(root), 'counter current, clock, notes');
expect('no page but the counter booted: no timers', timeouts.length + intervals.length, 0);
byRole(root, 'button', '+').listeners.click();
expect('the counter works', textOf(root, 'count'), '1');

root = await load('/pages/nope');
expect('an unknown page falls back to the counter', byId(root, 'counter') !== null, true);

// --- The clock page, pinned at the site root and under a prefix ---

for (const path of ['/clock', '/pages/clock', '/pages/clock/']) {
  root = await load(path);
  expect(`${path} shows the clock`, byId(root, 'clock') !== null && byId(root, 'counter') === null, true);
}
expect('each clock load scheduled its boot timer', timeouts.map((t) => t.ms).join(','), '0,0,0');
expect('each clock load started its tick subscription', intervals.map((i) => i.ms).join(','), '1000,1000,1000');
expect('clock links mark the clock', links(root), 'counter, clock current, notes');
now = 3_723_000;
timeouts[2].fn();
expect('boot tick set the time', textOf(root, 'time'), '01:02:03 UTC');
now = 3_724_000;
intervals[2].fn();
expect('tick advanced the time', textOf(root, 'time'), '01:02:04 UTC');
byRole(root, 'button', 'Lap').listeners.click();
expect('laps recorded', htmlBare(byId(root, 'laps')), '<li>01:02:04 UTC</li>');
byRole(root, 'button', 'Pause').listeners.click();
expect('pausing dropped the subscription', cleared, 1);

// --- The notes page ---

root = await load('/notes');
expect('notes page shows', byId(root, 'notes') !== null, true);
expect('notes links mark the notes', links(root), 'counter, clock, notes current');
const draft = () => byId(root, 'draft');
draft().listeners.input({ target: { value: 'buy milk' } });
draft().listeners.keydown({ key: 'Enter', preventDefault: () => {} });
draft().listeners.input({ target: { value: 'call mum' } });
byRole(root, 'button', 'Add').listeners.click();
expect('two notes', htmlBare(byId(root, 'list')), '<li>buy milk<button>x</button></li><li>call mum<button>x</button></li>');
byRoleAll(byId(root, 'list'), 'button', 'x')[0].listeners.click();
expect('delete removes that note only', htmlBare(byId(root, 'list')), '<li>call mum<button>x</button></li>');

// --- A message for a page not on screen is dropped ---

// A new load of the notes page has no clock model. A stale tick, as from a
// timer that outlived its page, arrives wrapped as a ClockMsg and the
// update's catch-all arm ignores it: nothing changes and nothing crashes.
const before = htmlBare(root);
timeouts[0].fn();
expect('a clock tick on the notes page changes nothing', htmlBare(root), before);
