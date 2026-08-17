// Node harness for the lazy_nested app: Html.lazy regions skip whole subtrees
// when their thunk captures are unchanged. An unchanged handler element emits
// no attribute writes even when its region is rediffed (it gets a compact
// handler-id refresh instead), so the harness asserts zero setAttr calls on
// the region buttons throughout and proves a forced rediff by its visible
// patch plus the handler staying live afterwards. Covers the nested case
// (outer forced while inner skips), handlers dispatching from inside skipped
// regions, rebuild on capture change, and dropping plus re-forcing a region
// via toggling.
// Run from the repo root: node tests/check_lazy_nested.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare, find } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

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
await mount({ wasm: readFileSync(wasmPath('lazy_nested')), root, flags: '', dom: countingDom });

const bump = find(root, 'bump');
const grow = find(root, 'grow');
const relabel = find(root, 'relabel');
const toggle = find(root, 'toggle');
const clicksShown = () => htmlBare(root).match(/clicks (\d+)/)[1];

expect('initial content', htmlBare(root).includes('label A'), true);
expect('initial deep', htmlBare(root).includes('deep 3'), true);
expect('initial items', htmlBare(root).includes('<li>item 3</li>'), true);

let innerBtn = find(root, 'inner');
let deepBtn = find(root, 'deep');

// Unrelated change: both lazy regions skip.
const [i0, d0] = [w(innerBtn), w(deepBtn)];
bump.listeners.click();
expect('clicks re-rendered', clicksShown(), '1');
expect('outer region skipped', w(innerBtn), i0);
expect('deep region skipped', w(deepBtn), d0);

// Handlers inside a skipped region stay live.
for (let i = 0; i < 5; i++) bump.listeners.click();
innerBtn.listeners.click();
deepBtn.listeners.click();
expect('handlers in skipped regions dispatch', clicksShown(), '8');

// Outer capture changes: outer is forced and rediffed (the label patch
// proves it), while the nested region still skips. The rediff rewrites no
// attrs on the unchanged button. Its handler ids are refreshed instead,
// which the dispatch check proves.
const [i1, d1] = [w(innerBtn), w(deepBtn)];
relabel.listeners.click();
expect('label patched', htmlBare(root).includes('label A!'), true);
expect('outer rediff rewrites no unchanged attrs', w(innerBtn), i1);
expect('nested region still skipped', w(deepBtn), d1);
expect('outer button patched in place', find(root, 'inner') === innerBtn, true);
const c1 = Number(clicksShown());
innerBtn.listeners.click();
expect('outer handler stays live across the rediff', clicksShown(), String(c1 + 1));

// Shared capture changes: both regions rebuild.
grow.listeners.click();
expect('items grew', htmlBare(root).includes('<li>item 4</li>'), true);
expect('deep rebuilt', htmlBare(root).includes('deep 4'), true);
expect('deep button patched in place', find(root, 'deep') === deepBtn, true);

// Skipping resumes after the rebuild.
const [i2, d2] = [w(innerBtn), w(deepBtn)];
bump.listeners.click();
expect('outer skips again', w(innerBtn), i2);
expect('deep skips again', w(deepBtn), d2);

// Toggle the whole region away (retained subtrees dropped) and back
// (forced fresh); handlers in the re-forced region dispatch.
toggle.listeners.click();
expect('region removed', htmlBare(root).includes('hidden'), true);
bump.listeners.click();
toggle.listeners.click();
expect('region back', htmlBare(root).includes('label A!'), true);
expect('deep back', htmlBare(root).includes('deep 4'), true);
innerBtn = find(root, 'inner');
deepBtn = find(root, 'deep');
const before = Number(clicksShown());
innerBtn.listeners.click();
deepBtn.listeners.click();
expect('handlers live after re-force', clicksShown(), String(before + 2));

// And the re-forced regions skip once retained.
const [i3, d3] = [w(innerBtn), w(deepBtn)];
bump.listeners.click();
expect('re-forced outer skips', w(innerBtn), i3);
expect('re-forced deep skips', w(deepBtn), d3);
