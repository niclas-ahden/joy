// `value` and `checked` name live DOM properties that drift as the user
// types or clicks, and a render that leaves the model unchanged writes
// nothing for them. The runtime pins the property back after the control's
// own event instead (see restoreControl in www/runtime.js). The app rejects
// text containing "!" and refuses to un-agree, so a rejected keystroke and a
// refused uncheck are exactly the unchanged-model dispatches the pin exists
// for. The budgets show the cost: an accepted change is one attribute patch
// and no pin, a rejected one is no patch and one property write.
// Run from the repo root: node tests/check_controlled_input.mjs
import { readFileSync } from 'node:fs';
import { El, byId } from './fakedom.mjs';
import { appRuntime, countingDom, expect, meter, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('controlled_input');

const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('controlled_input')), root, flags: '', dom: counted.dom });
const work = meter(app, counted);
const inp = byId(root, 'name');

expect('initial value pinned', inp.value, 'init');

// An accepted keystroke: the model takes it, the render writes it back, and
// the pin finds the property already right.
inp.value = 'ab';
work.mark();
inp.listeners.input({ target: { value: 'ab' } });
expect('accepted input lands in the DOM', inp.value, 'ab');
work.expectDelta('accepting is one attribute patch', { patchAttrs: 1, attrWrites: 1, propWrites: 0 });

// A rejected keystroke: the browser already shows the text, the model
// refuses it, the render emits nothing, and the pin snaps the property back.
inp.value = 'ab!';
work.mark();
inp.listeners.input({ target: { value: 'ab!' } });
expect('rejected input snaps back to the model', inp.value, 'ab');
work.expectDelta('rejecting is one property write', { patchAttrs: 0, attrWrites: 0, propWrites: 1 });

// Only the control's own event pins it. A property changed behind the
// runtime's back (a script, not the user) is left alone by unrelated
// renders, like any framework that trusts its own writes.
inp.value = 'poked from outside';
work.mark();
byId(root, 'tick').listeners.click();
expect('an unrelated render leaves a poked property alone', inp.value, 'poked from outside');
work.expectDelta('an unrelated render touches no input', { patchAttrs: 0, propWrites: 0 });

// `checked` declared false by the view: the DOM carries no attribute, which
// is also what an undeclared checkbox looks like, so the runtime remembers
// the declaration itself.
const cb = byId(root, 'agree');
expect('checkbox starts unchecked', cb.checked, false);
cb.checked = true;
work.mark();
cb.listeners.change({ target: cb });
expect('checking is accepted', cb.checked, true);
work.expectDelta('accepting a check is one attribute patch', { patchAttrs: 1, propWrites: 0 });

// Unchecking is refused: the browser already cleared the box, the model
// keeps it, and the pin restores it.
cb.checked = false;
work.mark();
cb.listeners.change({ target: cb });
expect('a refused uncheck snaps back', cb.checked, true);
work.expectDelta('refusing is one property write', { patchAttrs: 0, propWrites: 1 });

// --- controlled to uncontrolled and back ---
// "Pin" makes the view stop declaring `value` and `checked`. Removing the
// attributes clears the live state with them (an undeclared control starts
// from nothing), and from then on the controls are the user's: a refused
// change is not pinned, because there is nothing declared to pin to.
const pin = byId(root, 'pin');
work.mark();
pin.listeners.click();
expect('unpinning removes the value attribute', inp.attrs.has('value'), false);
expect('and clears the field with it', inp.value, '');
expect('unpinning removes the checked declaration', cb.attrs.has('checked'), false);
expect('and clears the box with it', cb.checked, false);
work.expectDelta('unpinning is two attribute removals', { attrRemovals: 2, propWrites: 0 });

inp.value = 'free!';
work.mark();
inp.listeners.input({ target: { value: 'free!' } });
expect('an uncontrolled input keeps refused text', inp.value, 'free!');
work.expectDelta('nothing to pin without a declaration', { patchAttrs: 0, propWrites: 0 });
inp.value = 'free';
inp.listeners.input({ target: { value: 'free' } });

cb.checked = true;
cb.listeners.change({ target: cb });
cb.checked = false;
work.mark();
cb.listeners.change({ target: cb });
expect('an uncontrolled checkbox keeps a refused uncheck', cb.checked, false);
work.expectDelta('nothing to pin for the checkbox either', { patchAttrs: 0, propWrites: 0 });

// Declaring them again re-asserts the model over whatever the DOM holds,
// including a value a script changed meanwhile.
inp.value = 'drifted';
work.mark();
pin.listeners.click();
expect('re-pinning restores the model value', inp.value, 'free');
expect('re-pinning restores the model checked state', cb.checked, true);
work.expectDelta('re-pinning writes both declarations', { attrWrites: 2, propWrites: 0 });
inp.value = 'free!';
work.mark();
inp.listeners.input({ target: { value: 'free!' } });
expect('and refusals pin again', inp.value, 'free');
work.expectDelta('a refusal after re-pinning', { patchAttrs: 0, propWrites: 1 });
