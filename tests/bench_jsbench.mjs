// js-framework-benchmark operations against the fake DOM, timed in Node. The
// fastest inner loop while optimizing the host or runtime: whole dispatches
// (update + render + diff + paint), no browser. Paint is the fake DOM, so
// treat it as a proxy and confirm wins in the js-framework-benchmark clone.
// Run from the repo root, naming the built tree under test:
//   JOY_OPT=speed node tests/bench_jsbench.mjs            # keyed
//   JOY_OPT=speed node tests/bench_jsbench.mjs --nonkeyed
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom } from './fakedom.mjs';
import { wasmPath } from './harness.mjs';

const keyed = !process.argv.includes('--nonkeyed');
const bytes = readFileSync(wasmPath(keyed ? 'jsbench_keyed' : 'jsbench_nonkeyed'));

function findId(node, id) {
  if (!(node instanceof El)) return null;
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children) {
    const hit = findId(c, id);
    if (hit) return hit;
  }
  return null;
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const tbody = findId(root, 'tbody');
const btn = {};
for (const id of ['run', 'runlots', 'add', 'update', 'clear', 'swaprows']) {
  btn[id] = findId(root, id).listeners;
}
const selectRow = (i) => tbody.children[i].children[1].children[0].listeners.click();
const removeRow = (i) => tbody.children[i].children[2].children[0].listeners.click();

// Each op: (setup, action). Timed over `runs` repetitions, median reported.
function time(name, runs, setup, action) {
  const times = [];
  for (let i = 0; i < runs; i++) {
    setup();
    const t0 = performance.now();
    action();
    times.push(performance.now() - t0);
  }
  console.log(`${name.padEnd(16)} ${median(times).toFixed(2).padStart(8)} ms`);
}

const ensure1k = () => { btn.clear.click(); btn.run.click(); };

console.log(`bracket: ${keyed ? 'keyed' : 'non-keyed'} (median ms per dispatch)`);
time('create 1k', 12, () => btn.clear.click(), () => btn.run.click());
time('replace 1k', 12, ensure1k, () => btn.run.click());
time('update 10th', 12, ensure1k, () => btn.update.click());
time('select row', 20, ensure1k, () => selectRow(3));
time('swap rows', 20, ensure1k, () => btn.swaprows.click());
time('remove row', 20, ensure1k, () => removeRow(5));
time('append 1k', 8, ensure1k, () => btn.add.click());
time('clear 1k', 12, ensure1k, () => btn.clear.click());
time('create 10k', 4, () => btn.clear.click(), () => btn.runlots.click());
