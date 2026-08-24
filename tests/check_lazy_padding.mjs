// Lazy skipping relies on byte-comparing thunk captures, so capture records
// holding sub-word fields (Bool in a tuple, Bool in a record, U8 next to a
// U64) must produce deterministic bytes: garbage padding would make equal
// inputs compare unequal and silently stop regions from skipping. This
// guards that compiler property through the host's lazy_forces counter:
// each group re-renders with unchanged inputs, and a capture that compares
// unequal forces its thunk again, growing the miss count. (DOM node
// identity cannot detect it: a forced-but-equal tree diffs to zero ops and
// keeps the same nodes.) Run from the repo root:
// node tests/check_lazy_padding.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('lazy_padding'));

function findId(node, id) {
  if (!(node instanceof El)) return null;
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children) {
    const hit = findId(c, id);
    if (hit) return hit;
  }
  return null;
}

const root = new El('#root');
const app = await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const ex = app.instance.exports;
const tick = findId(root, 'tick').listeners;
const groups = ['tuple-bool', 'record-bool', 'u8-mix'];

// Warm renders: one so every thunk has a retained entry, and two more to
// get the allocator recycling. The first recycled captures can carry
// garbage in their trailing padding (virgin memory is zeroed, recycled is
// not), which costs a one-time spurious re-force per thunk; see the
// lazy_same notes in host/host.rs. Steady state must then be miss-free.
for (let i = 0; i < 3; i++) tick.click();
const entries = ex.lazy_entries();
const forces = ex.lazy_forces();
const before = {};
for (const g of groups) before[g] = [...findId(root, g).children];
for (let i = 0; i < 5; i++) tick.click();
expect('unchanged captures never re-force', ex.lazy_forces(), forces);
expect('the retained entries all survive', ex.lazy_entries(), entries);
for (const g of groups) {
  const now = findId(root, g).children;
  expect(`${g}: the skipped DOM nodes survive`, now.every((n, i) => n === before[g][i]), true);
}
