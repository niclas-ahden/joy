// A `value` attribute names a live DOM property that drifts as the user
// types, so equality with the previous render proves nothing: every diff
// must re-pin the property to the model (see is_live_prop in host/host.rs).
// The app rejects input containing "!", so a rejected keystroke re-renders
// with an unchanged model, the exact case where a diff that skips unchanged
// attributes would leave the rejected text in the DOM.
// Run from the repo root: node tests/check_controlled_input.mjs
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
await mount({ wasm: readFileSync(wasmPath('controlled_input')), root, flags: '', dom: fakeDom });
const inp = findId(root, 'name');

expect('initial value pinned', inp.value, 'init');

// An accepted keystroke: the model takes it, the render writes it back.
inp.value = 'ab';
inp.listeners.input({ target: { value: 'ab' } });
expect('accepted input lands in the DOM', inp.value, 'ab');

// A rejected keystroke: the browser already shows the text, the model
// refuses it, and the re-render must snap the property back.
inp.value = 'ab!';
inp.listeners.input({ target: { value: 'ab!' } });
expect('rejected input snaps back to the model', inp.value, 'ab');

// Any unrelated re-render also re-pins a diverged property.
inp.value = 'poked from outside';
findId(root, 'tick').listeners.click();
expect('an unrelated render re-pins the value', inp.value, 'ab');
