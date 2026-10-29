// Node harness for the counter: drives it through Roc-declared on_click
// messages and asserts the rendered HTML, that the diff reused the existing
// DOM nodes (a text-only change must not rebuild the buttons), and that a
// click costs exactly one text write.
// Run from the repo root: node tests/check_counter.mjs
import { readFileSync } from 'node:fs';
import { El, byRole, html } from './fakedom.mjs';
import { appRuntime, countingDom, expect, meter, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('counter');

const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('counter')), root, flags: '', dom: counted.dom });
const work = meter(app, counted);
const click = (label) => byRole(root, 'button', label).listeners.click();

expect('init', html(root), '<div><button id="increment">+</button>0<button id="decrement">-</button></div>');

// Capture node identities before a click; a diffed text change must preserve them.
const plusBtn = byRole(root, 'button', '+');
const minusBtn = byRole(root, 'button', '-');
const countText = root.children[0].children[1]; // the text node between the buttons

work.mark();
click('+');
expect('after +', html(root), '<div><button id="increment">+</button>1<button id="decrement">-</button></div>');
expect('plus button reused', byRole(root, 'button', '+') === plusBtn, true);
expect('minus button reused', byRole(root, 'button', '-') === minusBtn, true);
expect('count text node reused (SET_TEXT in place)', root.children[0].children[1] === countText, true);
expect('count text value updated', countText.text, '1');
// The whole cost of a click is one SET_TEXT applied as one text write. The
// render re-boxes both buttons' handlers, which the differ refreshes in place
// rather than rebinding.
work.expectDelta('a click', {
  patchSetText: 1, textWrites: 1, patchRefresh: 2,
  patchReplace: 0, patchAttrs: 0, patchReorder: 0, elements: 0, bindings: 0,
});

click('+'); click('-');
expect('after +,-', html(root), '<div><button id="increment">+</button>1<button id="decrement">-</button></div>');
expect('buttons still the same nodes', byRole(root, 'button', '+') === plusBtn && byRole(root, 'button', '-') === minusBtn, true);
