// A keyed child among unkeyed siblings: identity lives on the key, so the
// differ must never pair the keyed element positionally with an unkeyed
// sibling (resolving strips the wrapper, and with it the key). A swap must
// MOVE the keyed element's DOM node, observable as object identity across
// the reorder.
// Run from the repo root: node tests/check_keyed_mixed.mjs
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
await mount({ wasm: readFileSync(wasmPath('keyed_mixed')), root, flags: '', dom: fakeDom });

const pair = () => findId(root, 'pair').children;
expect('keyed child starts second', pair()[1].attrs.get('id'), 'keyed');
const keyedNode = pair()[1];

findId(root, 'swap').listeners.click();
expect('keyed child is first after the swap', pair()[0].attrs.get('id'), 'keyed');
expect('its DOM node moved with its key', pair()[0], keyedNode);
expect('the unkeyed sibling still renders', pair()[1].children[0]?.text, 'P');
