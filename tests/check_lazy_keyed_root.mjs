// A thunk can return Html.keyed at its root, so resolving a lazy node must
// keep unwrapping after forcing: an unwrapped-before-forcing-only resolve
// emits nothing for the region (blank render) and later misreads the Keyed
// wrapper as an element in the diff.
// Run from the repo root: node tests/check_lazy_keyed_root.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

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
await mount({ wasm: readFileSync(wasmPath('lazy_keyed_root')), root, flags: '', dom: fakeDom });

expect('the keyed content inside the lazy region rendered', findId(root, 'kv')?.children[0]?.text, 'v0');

// A changed input replaces the forced tree, still through the wrapper.
findId(root, 'tick').listeners.click();
expect('a changed input re-renders the keyed content', findId(root, 'kv')?.children[0]?.text, 'v1');
