// A lazy Html value held in the model reaches the differ as the same thunk
// allocation every render, so its retained subtree is only ever reachable
// through cache hits. Swapping it between unkeyed positions pairs it against
// a non-lazy sibling, where a missed live mark once let the sweep free the
// subtree while the DOM and the just-emitted patch still referenced it (a
// use-after-free at the FFI boundary). The host's lazy_entries/lazy_forces
// counters make both failure modes observable: a swept entry shrinks the
// table, a re-force grows the miss count.
// Run from the repo root: node tests/check_lazy_retained.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('lazy_retained'));

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
const textOf = (id) => findId(root, id).children[0]?.text;

expect('one retained entry after mount', ex.lazy_entries(), 1);
const forces = ex.lazy_forces();

findId(root, 'swap').listeners.click();

expect('the entry survives the move', ex.lazy_entries(), 1);
expect('the move is a hit, not a re-force', ex.lazy_forces(), forces);
// Unkeyed cross-kind moves rebuild the DOM nodes (identity needs keys), but
// they are built FROM the retained subtree, which must still be alive.
expect('the moved region shows the retained content', findId(root, 'pair').children[0]?.children[0]?.children[0]?.text, 'row 1');

// The handler box lives in the retained subtree. Before the sweep fix this
// dispatch went through freed memory.
findId(root, 'inner').listeners.click();
expect('the retained handler still dispatches', textOf('clicks'), '1');

findId(root, 'swap').listeners.click();
findId(root, 'inner').listeners.click();
expect('and again after swapping back', textOf('clicks'), '2');
expect('entry count stable across both moves', ex.lazy_entries(), 1);
expect('force count stable across both moves', ex.lazy_forces(), forces);
