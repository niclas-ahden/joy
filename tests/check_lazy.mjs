// Node harness for the lazy demo app: a 16 ms ticker next to a big card
// grid, with Html.lazy toggleable at runtime. An unchanged grid produces no
// attribute writes whether it was rediffed or skipped (a rediffed handler
// element gets a compact handler-id refresh instead of an attribute
// rewrite), so the harness asserts what each mode promises: the spinner
// animates either way, the grid button's attrs are never rewritten, its
// node is reused, and its handler keeps dispatching after ticks in both
// modes (with lazy OFF that is the id refresh keeping it live). Also
// asserts that growing the grid rebuilds it and that skipping resumes.
// Run from the repo root: node tests/check_lazy.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

// Deterministic clock + captured intervals (same scheme as check_time.mjs).
const T0 = 1_754_000_000_000;
let nowMs = T0;
Date.now = () => nowMs;
const intervals = [];
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = () => {};

const writes = new Map();
const countingDom = {
  ...fakeDom,
  setAttr: (node, k, v) => {
    writes.set(node, (writes.get(node) ?? 0) + 1);
    fakeDom.setAttr(node, k, v);
  },
};
const w = (node) => writes.get(node) ?? 0;

const root = new El('#root');
await mount({ wasm: readFileSync('build/lazy.wasm'), root, flags: '', dom: countingDom });

expect('ticker subscribed at 16ms', intervals.length === 1 && intervals[0].ms === 16, true);
const tick = () => { nowMs += 16; intervals[0].fn(); };

const cardCount = () => (htmlBare(root).match(/Visa bostad/g) ?? []).length;
expect('grid rendered at initial size', cardCount(), 4000);

// Shrink to keep the harness snappy: 4000 -> 1000.
find(root, '÷2').listeners.click();
find(root, '÷2').listeners.click();
expect('rows halved twice', cardCount(), 1000);

const gridBtn = find(root, 'a button inside the grid');
const spinner = () => htmlBare(root).match(/([◐◓◑◒])/)[1];

// Lazy OFF (the default): every tick rediffs the grid, but an unchanged
// element emits no attribute writes. Only its handler ids are refreshed,
// and the dispatch check proves that refresh kept the handler live.
const s0 = spinner();
const w0 = w(gridBtn);
tick();
tick();
expect('spinner animates with lazy off', spinner() !== s0, true);
expect('rediff rewrites no unchanged grid attrs', w(gridBtn), w0);
const sA = spinner();
gridBtn.listeners.click();
expect('grid handler stays live across rediffs', spinner() !== sA, true);

// Lazy ON: ticks no longer touch the grid at all.
find(root, 'Html.lazy: OFF').listeners.click();
const w1 = w(gridBtn);
const s1 = spinner();
tick();
tick();
tick();
expect('spinner still animates with lazy on', spinner() !== s1, true);
expect('grid skipped on every tick with lazy on', w(gridBtn), w1);
expect('grid button node reused', find(root, 'a button inside the grid') === gridBtn, true);
expect('gap meter shows the tick cadence', htmlBare(root).includes('tick gap 16.0 ms'), true);

// A handler inside the skipped region still dispatches (spinner advances).
const s2 = spinner();
gridBtn.listeners.click();
expect('handler inside skipped region dispatches', spinner() !== s2, true);

// Changing the captured input rebuilds the grid, then skipping resumes.
find(root, '×2').listeners.click();
expect('grid rebuilt on rows change', cardCount(), 2000);
const w2 = w(gridBtn);
tick();
expect('skip resumes after rebuild', w(gridBtn), w2);
