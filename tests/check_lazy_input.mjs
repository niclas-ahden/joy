// A controlled input inside Html.lazy. A rejected keystroke leaves the
// thunk's capture equal, so the render skips the whole region and no
// attribute op reaches the input. The property pin runs after the event
// rather than inside the render, so the model's value still wins there.
// Run from the repo root: node tests/check_lazy_input.mjs
import { readFileSync } from 'node:fs';
import { El, byId } from './fakedom.mjs';
import { appRuntime, countingDom, expect, meter, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('lazy_input');

const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('lazy_input')), root, flags: '', dom: counted.dom });
const work = meter(app, counted);
const inp = byId(root, 'name');

expect('initial value pinned', inp.value, 'init');

// Accepted: the capture changes, the thunk is forced, the value written.
inp.value = 'ab';
work.mark();
inp.listeners.input({ target: { value: 'ab' } });
expect('accepted input lands in the DOM', inp.value, 'ab');
work.expectDelta('a changed capture forces the thunk', { lazyForces: 1, patchAttrs: 1, propWrites: 0 });

// Rejected: the capture is unchanged and no attribute op reaches the input,
// yet the property is pinned back. The first render after a capture change
// re-forces the thunk once (a recycled-memory quirk of the capture
// comparison, see check_lazy_padding.mjs), so the skip itself is proved on
// the second rejection.
inp.value = 'ab!';
work.mark();
inp.listeners.input({ target: { value: 'ab!' } });
expect('rejected input snaps back to the model', inp.value, 'ab');
work.expectDelta('rejecting is one property write', { patchAttrs: 0, attrWrites: 0, propWrites: 1 });
inp.value = 'ab!!';
work.mark();
inp.listeners.input({ target: { value: 'ab!!' } });
expect('rejected input snaps back inside the skipped region', inp.value, 'ab');
work.expectDelta('the region was skipped and the property pinned', { lazyForces: 0, patchAttrs: 0, attrWrites: 0, propWrites: 1 });
