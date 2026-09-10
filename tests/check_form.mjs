// A 200-row form with every kind of control. Two properties, per control
// kind: a change to one control costs work proportional to that control
// (one attribute patch, one DOM write) and never to the form, and a change
// the update refuses snaps the control back to the model at the cost of one
// property write and no patch at all. Radio groups and selects move
// sibling state without an event of their own, so their refusals pin two
// properties. The end covers IME composition, where the pin waits for the
// composition to end, in both event orders browsers use.
// Run from the repo root: node tests/check_form.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, byId, byRoleAll } from './fakedom.mjs';
import { countingDom, expect, meter, wasmPath } from './harness.mjs';

const N = 200;
const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('form')), root, flags: JSON.stringify({ n: N }), dom: counted.dom });
const work = meter(app, counted);

// Every control carries a handler: the tick button, three radios, the
// select, the quantity, the notes, the code, and a text and a checkbox per
// row.
const CONTROLS = 1 + 3 + 1 + 1 + 1 + 1 + 2 * N;
const type = (el, v) => { el.value = v; el.listeners.input({ target: { value: v } }); };
const t = (i) => byId(root, `t${i}`);
const c = (i) => byId(root, `c${i}`);

// Textboxes: one per row, the notes and the code.
expect('every row rendered', byRoleAll(root, 'textbox').length, N + 2);
expect('a row starts from the model', t(17).value, 'row 17');

// --- text: O(1) per keystroke, whatever the form size ---
work.mark();
type(t(17), 'row 17x');
expect('accepted text lands', t(17).value, 'row 17x');
work.expectDelta('an accepted keystroke in one of 200 rows', {
  patchAttrs: 1, attrWrites: 1, propWrites: 0, patchReplace: 0, patchReorder: 0, elements: 0, textWrites: 0,
});
work.mark();
type(t(17), 'row 17x!');
expect('refused text snaps back', t(17).value, 'row 17x');
work.expectDelta('a refused keystroke', { patchAttrs: 0, attrWrites: 0, propWrites: 1, elements: 0 });
// What a render still costs per control: the handler refresh, one compact
// op per handler element because every render re-boxes its handlers. No
// DOM writes come of it. This is the O(controls) term left in a keystroke.
work.expectDelta('handler refresh is the per-control cost', { patchRefresh: CONTROLS });

// --- checkbox: checking is accepted, unchecking refused ---
c(3).checked = true;
work.mark();
c(3).listeners.change({ target: c(3) });
expect('checking is accepted', c(3).checked, true);
work.expectDelta('an accepted check', { patchAttrs: 1, propWrites: 0 });
c(3).checked = false;
work.mark();
c(3).listeners.change({ target: c(3) });
expect('refused uncheck snaps back', c(3).checked, true);
work.expectDelta('a refused uncheck', { patchAttrs: 0, propWrites: 1 });

// --- radio group: the browser moves the whole group before the event ---
const red = byId(root, 'color-red');
const green = byId(root, 'color-green');
const blue = byId(root, 'color-blue');
const colors = () => `${red.checked},${green.checked},${blue.checked}`;
expect('red starts checked', colors(), 'true,false,false');
green.checked = true; red.checked = false;
work.mark();
green.listeners.change({ target: green });
expect('green is accepted', colors(), 'false,true,false');
work.expectDelta('an accepted radio moves two attributes', { patchAttrs: 2, propWrites: 0 });
blue.checked = true; green.checked = false;
work.mark();
blue.listeners.change({ target: blue });
expect('refused blue snaps the group back to green', colors(), 'false,true,false');
work.expectDelta('a refused radio pins the target and its mate', { patchAttrs: 0, propWrites: 2 });

// --- select with optgroups: options move with the select's change ---
const size = byId(root, 'size');
const opt = (v) => byRoleAll(size, 'option').find((o) => o.attrs.get('value') === v);
const sizes = () => ['s', 'm', 'l', 'xl'].map((v) => (opt(v).selected ? v : '-')).join(',');
expect('S starts selected', sizes(), 's,-,-,-');
opt('s').selected = false; opt('m').selected = true; size.value = 'm';
work.mark();
size.listeners.change({ target: size });
expect('M is accepted', sizes(), '-,m,-,-');
work.expectDelta('an accepted pick moves two attributes', { patchAttrs: 2, propWrites: 0 });
opt('m').selected = false; opt('xl').selected = true; size.value = 'xl';
work.mark();
size.listeners.change({ target: size });
expect('refused XL snaps back to M', sizes(), '-,m,-,-');
work.expectDelta('a refused pick pins both options', { patchAttrs: 0, propWrites: 2 });

// --- number ---
const qty = byId(root, 'qty');
work.mark();
type(qty, '5');
expect('a quantity in range lands', qty.value, '5');
work.expectDelta('an accepted quantity', { patchAttrs: 1, propWrites: 0 });
work.mark();
type(qty, '50');
expect('a quantity out of range snaps back', qty.value, '5');
work.expectDelta('a refused quantity', { patchAttrs: 0, propWrites: 1 });

// --- textarea ---
const notes = byId(root, 'notes');
work.mark();
type(notes, 'hi');
expect('notes accepted', notes.value, 'hi');
work.expectDelta('an accepted textarea keystroke', { patchAttrs: 1, propWrites: 0 });
work.mark();
type(notes, 'hi!');
expect('refused notes snap back', notes.value, 'hi');
work.expectDelta('a refused textarea keystroke', { patchAttrs: 0, propWrites: 1 });

// --- normalizing update: the model keeps its own version of the input ---
// An accepted keystroke whose normalized form differs from what was typed
// is an attribute patch that rewrites the property. One that normalizes to
// the unchanged model (a space, dropped) takes the refusal path: no patch,
// one pin.
const code = byId(root, 'code');
work.mark();
type(code, 'ab');
expect('typed text lands normalized', code.value, 'AB');
work.expectDelta('a normalized keystroke', { patchAttrs: 1, attrWrites: 1, propWrites: 0 });
work.mark();
type(code, 'AB ');
expect('a dropped space snaps back to the model', code.value, 'AB');
work.expectDelta('a keystroke normalized away', { patchAttrs: 0, attrWrites: 0, propWrites: 1 });
work.mark();
type(code, 'AxB');
expect('a mid-value keystroke lands normalized', code.value, 'AXB');
work.expectDelta('a normalized mid-value keystroke', { patchAttrs: 1, attrWrites: 1, propWrites: 0 });

// --- IME composition: provisional text is never pinned mid-composition ---
// Chromium's order, and Firefox's for its own IME typing: input events with
// isComposing during the composition, then compositionend. A refusal
// mid-composition leaves the provisional text alone and pins once the
// composition ends.
const compose = (el, v) => { el.value = v; el.listeners.input({ target: { value: v }, isComposing: true }); };
work.mark();
compose(notes, 'hi日');
expect('accepted composing text lands', notes.value, 'hi日');
work.expectDelta('an accepted composing keystroke', { patchAttrs: 1, propWrites: 0 });
work.mark();
compose(notes, 'hi日!');
expect('refused composing text is left provisional', notes.value, 'hi日!');
work.expectDelta('no pin mid-composition', { patchAttrs: 0, propWrites: 0 });
notes.listeners.compositionend({});
expect('the pin runs when the composition ends', notes.value, 'hi日');
work.expectDelta('one pin at compositionend', { propWrites: 1 });
// Firefox's ending: compositionend with the text committed, then one input
// without isComposing. Playwright's fill on Firefox takes this path with
// no input during the composition at all, which is what is modelled here
// and what tests/e2e/form_test.roc drives for real. The runtime delivers
// the committed text at compositionend, so an accepted composition lands
// (one attribute patch, no pin) and a refused one is reverted before the
// trailing input, which then carries the settled value.
work.mark();
notes.value = 'hi日x';
notes.listeners.compositionend({});
expect('compositionend delivers accepted text', notes.value, 'hi日x');
notes.listeners.input({ target: { value: notes.value }, isComposing: false });
expect('the trailing input changes nothing', notes.value, 'hi日x');
work.expectDelta('an accepted composition in that order', { patchAttrs: 1, propWrites: 0 });
work.mark();
notes.value = 'hi日x!';
notes.listeners.compositionend({});
expect('compositionend reverts refused text', notes.value, 'hi日x');
notes.listeners.input({ target: { value: notes.value }, isComposing: false });
expect('the trailing input keeps the model value', notes.value, 'hi日x');
work.expectDelta('a refused composition in that order', { patchAttrs: 0, propWrites: 1 });
