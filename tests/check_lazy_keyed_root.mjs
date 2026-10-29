// A thunk can return Html.keyed at its root, so resolving a lazy node must
// keep unwrapping after forcing: an unwrapped-before-forcing-only resolve
// emits nothing for the region (blank render) and later misreads the Keyed
// wrapper as an element in the diff.
// Run from the repo root: node tests/check_lazy_keyed_root.mjs
import { readFileSync } from 'node:fs';
import { El, byId, fakeDom } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('lazy_keyed_root');

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('lazy_keyed_root')), root, flags: '', dom: fakeDom });

expect('the keyed content inside the lazy region rendered', byId(root, 'kv')?.children[0]?.text, 'v0');

// A changed input replaces the forced tree, still through the wrapper.
byId(root, 'tick').listeners.click();
expect('a changed input re-renders the keyed content', byId(root, 'kv')?.children[0]?.text, 'v1');
