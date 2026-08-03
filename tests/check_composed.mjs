// Node harness for composed: two instances of a self-contained counter
// component embedded with Html.map, its boot effect routed with Effect.map and
// its tick subscription routed with Sub.map. Messages must reach the RIGHT
// instance, and only it.
// Run from the repo root: node tests/check_composed.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare } from './fakedom.mjs';
import { expect } from './harness.mjs';

// All elements matching pred, pre-order.
const collect = (node, pred, out = []) => {
  if (node instanceof El) {
    if (pred(node)) out.push(node);
    for (const c of node.children) collect(c, pred, out);
  }
  return out;
};

// Captured timers (the boot Effect uses setTimeout, the tick Sub setInterval).
const timeouts = [];
const intervals = [];
globalThis.setTimeout = (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; };
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = () => {};

const root = new El('#root');
await mount({ wasm: readFileSync('build/composed.wasm'), root, flags: '', dom: fakeDom });

const counters = () => htmlBare(root).match(/<h2>left<\/h2><div><button>-<\/button>(-?\d+)<button>\+<\/button><\/div><h2>right<\/h2><div><button>-<\/button>(-?\d+)<button>\+<\/button><\/div>/)?.slice(1, 3).join(',');

expect('both counters render at 0', counters(), '0,0');
expect('boot effect scheduled a timeout', timeouts.length === 1 && timeouts[0].ms === 5, true);
expect('tick subscription started an interval', intervals.length === 1 && intervals[0].ms === 1000, true);

// Effect.map: the component's boot effect was wrapped with Right(m), so firing
// it increments ONLY the right counter.
timeouts[0].fn();
expect('Effect.map routed the boot msg to the right counter', counters(), '0,1');

// Sub.map: the tick subscription was wrapped with Left(m).
intervals[0].fn();
expect('Sub.map routed the tick to the left counter', counters(), '1,1');
intervals[0].fn();
expect('ticks keep routing left', counters(), '2,1');

// Html.map: the two embedded views produce identical CounterMsgs; each must
// arrive wrapped for its own instance.
const [leftMinus, rightMinus] = collect(root, (n) => n.tag === 'button' && n.children[0]?.text === '-');
const [leftPlus, rightPlus] = collect(root, (n) => n.tag === 'button' && n.children[0]?.text === '+');
leftPlus.listeners.click();
expect('left + routes to the left instance', counters(), '3,1');
rightMinus.listeners.click();
expect('right - routes to the right instance', counters(), '3,0');
leftMinus.listeners.click();
rightPlus.listeners.click();
expect('every handler stays bound to its instance', counters(), '2,1');

