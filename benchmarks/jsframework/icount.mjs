#!/usr/bin/env node
// Count what each js-framework-benchmark CPU benchmark costs a Joy entry, exactly.
//
// Usage:
//   node icount.mjs <runtime.js> <instrumented.wasm>
//
// The wasm must come out of benchmarks/icount, which makes it count the
// instructions it executes. This replays every benchmark's warmups and its
// measured click on the fake DOM from tests/, then prints one JSON object
// with the cost of the measured click alone:
//
//   instr  wasm instructions executed
//   bulk   bytes moved by memory.copy and memory.fill
//   dom    calls the runtime made into the DOM
//
// The browser's timings move with whatever else the machine is doing, these
// numbers do not. The same binary gives the same counts on any machine and
// on every run, so a change of 0.1% is a real change. What they cannot see is
// the browser's own share (style, layout, paint) and how well the engine
// compiles the wasm, which is why they sit beside the timings, not in place
// of them.
//
// The steps mirror webdriver-ts/src/benchmarksPlaywright.ts: warmupCount is 5
// (3 for update every 10th), select row clicks row 5 and then row 2,
// and remove row skips 4 rows.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { El, fakeDom } from '../../tests/fakedom.mjs';

const [runtimePath, wasmPath] = process.argv.slice(2);
if (!runtimePath || !wasmPath) {
  console.error('usage: node icount.mjs <runtime.js> <instrumented.wasm>');
  process.exit(2);
}
const { mount } = await import(pathToFileURL(runtimePath).href);
const bytes = readFileSync(wasmPath);

const warmups = 5;
const rowsToSkip = 4;

// The published entry ships an older runtime, which removed a node through
// its parent.
const compat = { removeChild: (_parent, node) => fakeDom.remove(node) };

let domCalls = 0;
const dom = Object.fromEntries(
  Object.entries({ ...compat, ...fakeDom }).map(([k, f]) => [k, typeof f === 'function' ? (...a) => { domCalls++; return f(...a); } : f]),
);

// The runtime keeps the instance to itself, so catch its exports on the way
// past to read the counters.
let exports;
const instantiate = WebAssembly.instantiate;
WebAssembly.instantiate = async (...a) => {
  const r = await instantiate(...a);
  exports = (r.instance ?? r).exports;
  return r;
};

const findId = (n, id) => {
  if (!(n instanceof El)) return null;
  if (n.attrs.get('id') === id) return n;
  for (const c of n.children) {
    const hit = findId(c, id);
    if (hit) return hit;
  }
  return null;
};

// A fresh app per benchmark, as the runner opens a fresh page for each.
async function measure(warm, op) {
  const root = new El('div');
  await mount({ wasm: bytes, root, flags: '', dom });
  if (!exports.__icount) throw new Error(`${wasmPath} is not instrumented, run it through benchmarks/icount first`);
  const rows = () => findId(root, 'tbody').children;
  const page = {
    click: (id) => findId(root, id).listeners.click(),
    select: (i) => rows()[i].children[1].children[0].listeners.click(),
    remove: (i) => rows()[i].children[2].children[0].listeners.click(),
  };
  warm(page);
  const i0 = exports.__icount.value;
  const b0 = exports.__bulk_bytes.value;
  const d0 = domCalls;
  op(page);
  return {
    instr: Number(exports.__icount.value - i0),
    bulk: Number(exports.__bulk_bytes.value - b0),
    dom: domCalls - d0,
  };
}

const runClear = (p) => {
  for (let i = 0; i < warmups; i++) {
    p.click('run');
    p.click('clear');
  }
};
const benches = {
  '01_run1k': [runClear, (p) => p.click('run')],
  '02_replace1k': [(p) => { for (let i = 0; i < warmups; i++) p.click('run'); }, (p) => p.click('run')],
  '03_update10th1k_x16': [(p) => { p.click('run'); for (let i = 0; i < 3; i++) p.click('update'); }, (p) => p.click('update')],
  '04_select1k': [(p) => { p.click('run'); p.select(4); }, (p) => p.select(1)],
  '05_swap1k': [(p) => { p.click('run'); for (let i = 0; i <= warmups; i++) p.click('swaprows'); }, (p) => p.click('swaprows')],
  '06_remove-one-1k': [
    (p) => {
      p.click('run');
      for (let i = 0; i < warmups; i++) p.remove(warmups - i + rowsToSkip - 1);
      p.remove(rowsToSkip + 2 - 1);
    },
    (p) => p.remove(rowsToSkip - 1),
  ],
  '07_create10k': [runClear, (p) => p.click('runlots')],
  '08_create1k-after1k_x2': [(p) => { runClear(p); p.click('run'); }, (p) => p.click('add')],
  '09_clear1k_x8': [(p) => { runClear(p); p.click('run'); }, (p) => p.click('clear')],
};

const out = {};
for (const [id, [warm, op]] of Object.entries(benches)) out[id] = await measure(warm, op);
console.log(JSON.stringify(out));
