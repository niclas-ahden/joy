// Node harness for the boxy_grow app: Joy's heap must keep working after
// Roc's boxy runtime has grown linear memory behind the host allocator's back.
// The app's Time.every subscription links the boxy runtime, whose bookkeeping
// takes pages straight from memory.grow. The first tick renders enough rows
// that the host allocator has to grow too. A host that assumes it is the only
// one growing hands out the runtime's pages a second time and the render
// traps (issue #15). Each row count mounts a fresh instance, so the heap
// layout of one case cannot mask another.
// Run from the repo root: node tests/check_boxy_grow.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

// Captured intervals, so the tick fires on demand.
const intervals = [];
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = () => {};

const bytes = readFileSync(wasmPath('boxy_grow'));

for (const rows of [1000, 5000]) {
  const root = new El('#root');
  const before = intervals.length;
  await mount({ wasm: bytes, root, flags: String(rows), dom: fakeDom });
  expect(`${rows} rows: one interval started from the subscription`, intervals.length - before, 1);
  expect(`${rows} rows: mounted empty`, root.children[0].children.length, 0);

  // The trap, when it happens, surfaces here as a RuntimeError from the wasm
  // call, so catch it and report it as the failure rather than dying mid-run.
  let trap = null;
  try {
    intervals[before].fn();
  } catch (e) {
    trap = String(e);
  }
  expect(`${rows} rows: first tick renders without trapping`, trap, null);
  expect(`${rows} rows: every row rendered`, root.children[0].children.length, rows);
  expect(`${rows} rows: last row has its index`, find(root, String(rows - 1)) !== null, true);
}
