// Node harness for stop_propagation: the runtime must call the DOM event's
// stopPropagation() for a flagged handler and leave it alone for a plain one.
// The fake DOM has no bubble phase, so the harness plays browser: it fires the
// button's listener with an event that records stopPropagation calls, then
// forwards to the outer div's listener unless the event was stopped.
// Run from the repo root: node tests/check_stop_propagation.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('stop_propagation'));

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });

expect('init', htmlBare(root).includes('outer 0, inner 0'), true);

const outer = root.children[0];
expect('outer div listens for click', outer.listenerCount('click'), 1);

// One bubbled click: the button first, then the div, like a browser would.
const clickThrough = (label) => {
  const ev = { stopped: false, stopPropagation() { this.stopped = true; } };
  find(root, label).listeners.click(ev);
  if (!ev.stopped) outer.listeners.click(ev);
  return ev;
};

// The plain on_click lets the event travel on, so both counters move.
const bubbled = clickThrough('bubbles');
expect('plain handler leaves the event alone', bubbled.stopped, false);
expect('bubbled click reaches both', htmlBare(root).includes('outer 1, inner 1'), true);

// The flagged on_click swallows the event, so the div never hears about it.
const stopped = clickThrough('stops');
expect('flagged handler stops the event', stopped.stopped, true);
expect('stopped click moves only inner', htmlBare(root).includes('outer 1, inner 2'), true);

// The flag is per handler, so the plain button still bubbles afterwards.
const again = clickThrough('bubbles');
expect('plain handler still bubbles', again.stopped, false);
expect('counts after the mix', htmlBare(root).includes('outer 2, inner 3'), true);

// A click on the div itself moves only the outer counter.
const ev = { stopped: false, stopPropagation() { this.stopped = true; } };
outer.listeners.click(ev);
expect('direct outer click', htmlBare(root).includes('outer 3, inner 3'), true);
