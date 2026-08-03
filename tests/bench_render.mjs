// Render micro-benchmark, not part of tests.roc (no check_ prefix). Mounts
// build/bench_grid.wasm at several grid sizes and times header-only
// messages: each dispatch runs update + render + diff + paint synchronously,
// so the wall time per dispatch is the cost of re-rendering a page whose
// large card grid did not change. Run from the repo root:
//   node tests/bench_render.mjs
// Compare a lazy grid by passing lazy flags once the app supports it:
//   node tests/bench_render.mjs --lazy
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find } from './fakedom.mjs';

const lazy = process.argv.includes('--lazy');
const bytes = readFileSync('build/bench_grid.wasm');

const WARMUP = 30;
const RUNS = 200;

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

async function bench(n) {
  const root = new El('#root');
  await mount({ wasm: bytes, root, flags: JSON.stringify({ n, lazy }), dom: fakeDom });
  const typeBtn = find(root, 'type');
  const tickBtn = find(root, 'tick');

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
  return { type: median(typeTimes), tick: median(tickTimes) };
}

console.log(`mode: ${lazy ? 'lazy grid' : 'plain grid'} (median of ${RUNS} dispatches, ms)`);
console.log('cards | keystroke | hero tick');
for (const n of [100, 300, 1000]) {
  const r = await bench(n);
  console.log(`${String(n).padStart(5)} | ${r.type.toFixed(3).padStart(9)} | ${r.tick.toFixed(3).padStart(9)}`);
}
