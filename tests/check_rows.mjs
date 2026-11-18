// Node harness for an event that passes several handlers on its way up. Each
// was written for the view the event happened in, so each runs with the
// message it had then, and the view is rendered once after the last.
// tests/apps/rows.roc has rows that a click selects, each with a button that
// deletes it: the click on the button passes the button's handler, which
// removes the row, and then the row's.
// The fake DOM has no bubble phase, so the harness plays browser: one event
// goes to each element on the way in turn, unless one of them stopped it.
// Run from the repo root: JOY_OPT=speed node tests/check_rows.mjs
import { readFileSync } from 'node:fs';
import { El, byId, fakeDom } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('rows');

// The app's clock ticks only when a check says so.
const intervals = [];
globalThis.setInterval = (fn) => { intervals.push(fn); return intervals.length; };
globalThis.clearInterval = () => {};

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('rows')), root, flags: '', dom: fakeDom });

const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');
const log = () => textOf(byId(root, 'log'));
const rows = (list) => byId(root, list).children.map((li) => li.attrs.get('id')).join(',');

// A click on `first` that bubbles through `rest`, the elements above it as
// they are when the click happens, as a browser fixes an event's way before
// the first listener runs.
const click = (first, ...rest) => {
  const way = [first, ...rest].map((id) => byId(root, id));
  const ev = { bubbles: true, stopped: false, stopPropagation() { this.stopped = true; } };
  for (const node of way) {
    if (ev.stopped) break;
    node.listeners.click?.(ev);
  }
};

// --- A plain list: the row's element is reused for the next row ---

click('plain-del-beta', 'plain-beta');
expect('the row hears the click its button deleted it on', log(), 'deleted beta, selected beta');
expect('the row is gone', rows('plain'), 'plain-alpha,plain-gamma,plain-delta');

click('plain-del-delta', 'plain-delta');
expect('the last row, whose element is removed, hears it too', log(), 'deleted beta, selected beta, deleted delta, selected delta');
expect('the last row is gone', rows('plain'), 'plain-alpha,plain-gamma');

// --- A keyed list: the row's element is removed ---

click('keyed-del-beta', 'keyed-beta');
expect('a keyed row hears the click that deleted it', log().endsWith('deleted beta, selected beta'), true);
expect('the keyed row is gone', rows('keyed'), 'keyed-alpha,keyed-gamma,keyed-delta');

// --- A handler above says what the view showed when the click happened ---

click('flip', 'outer');
expect('the handler above is the one of the view the click happened in', log().endsWith('flipped, saw plain'), true);
click('flip', 'outer');
expect('and of the next view the next time', log().endsWith('flipped, saw flipped'), true);

// --- A click on a row alone is one message ---

click('plain-alpha');
expect('a click on the row selects it', log().endsWith('selected alpha'), true);

// --- An element that was not on the way when the click happened hears nothing ---

// The harness sends the same click on to an element the browser would not:
// one whose handler the view got after the click.
const ev = { bubbles: true, stopPropagation() {} };
byId(root, 'plain-del-alpha').listeners.click(ev);
const before = log();
byId(root, 'outer').listeners.click(ev);
expect('a handler that was not on the way stays out of it', log(), before);

expect('the page matches the model', rows('plain'), 'plain-gamma');
