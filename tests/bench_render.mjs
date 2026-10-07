// Render micro-benchmark, not part of tests.roc (no check_ prefix). Mounts
// the built bench_grid app at several grid sizes and times header-only
// messages: each dispatch runs update + render + diff + paint synchronously,
// so the wall time per dispatch is the cost of re-rendering a page whose
// large card grid did not change. "swap" and "rotate" change the header's
// shape (a replaced element, two reordered lists), which also times how the
// runtime keeps its node list after a structural paint. Run from the repo root, naming the built
// tree under test:
//   JOY_OPT=speed node tests/bench_render.mjs
// Compare a lazy grid by passing lazy flags once the app supports it:
//   JOY_OPT=speed node tests/bench_render.mjs --lazy
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, find, uncheckedDom } from './fakedom.mjs';
import { wasmPath } from './harness.mjs';

const lazy = process.argv.includes('--lazy');
const bytes = readFileSync(wasmPath('bench_grid'));

const WARMUP = 30;
const RUNS = 200;

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

async function bench(n) {
  const root = new El('#root');
  await mount({ wasm: bytes, root, flags: JSON.stringify({ n, lazy }), dom: uncheckedDom });
  const typeBtn = find(root, 'type');
  const tickBtn = find(root, 'tick');
  const swapBtn = find(root, 'swap');
  const rotateBtn = find(root, 'rotate');

  const measure = (btn) => {
    for (let i = 0; i < WARMUP; i++) btn.listeners.click();
    const times = [];
    for (let i = 0; i < RUNS; i++) {
      const t0 = performance.now();
      btn.listeners.click();
      times.push(performance.now() - t0);
    }
    return times;
  };

  const typeTimes = measure(typeBtn);
  const tickTimes = measure(tickBtn);
  const swapTimes = measure(swapBtn);
  const rotateTimes = measure(rotateBtn);
  return { type: median(typeTimes), tick: median(tickTimes), swap: median(swapTimes), rotate: median(rotateTimes) };
}

console.log(`mode: ${lazy ? 'lazy grid' : 'plain grid'} (median of ${RUNS} dispatches, ms)`);
console.log('cards | keystroke | hero tick |      swap |    rotate');
for (const n of [100, 300, 1000]) {
  const r = await bench(n);
  console.log(`${String(n).padStart(5)} | ${r.type.toFixed(3).padStart(9)} | ${r.tick.toFixed(3).padStart(9)} | ${r.swap.toFixed(3).padStart(9)} | ${r.rotate.toFixed(3).padStart(9)}`);
}
