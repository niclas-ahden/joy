// Node harness for the counter: drives it through Roc-declared on_click
// messages and asserts both the rendered HTML and that the diff reused existing
// DOM nodes (a text-only change must not rebuild the buttons).
// Run from the repo root: node tests/check_counter.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

const bytes = readFileSync('build/counter.wasm');

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const click = (label) => { const el = find(root, label); el.listeners.click(); };

expect('init', html(root), '<div><button>+</button>0<button>-</button></div>');

// Capture node identities before a click; a diffed text change must preserve them.
const plusBtn = find(root, '+');
const minusBtn = find(root, '-');
const countText = root.children[0].children[1]; // the text node between the buttons

click('+');
expect('after +', html(root), '<div><button>+</button>1<button>-</button></div>');
expect('plus button reused', find(root, '+') === plusBtn, true);
expect('minus button reused', find(root, '-') === minusBtn, true);
expect('count text node reused (SET_TEXT in place)', root.children[0].children[1] === countText, true);
expect('count text value updated', countText.text, '1');

click('+'); click('-');
expect('after +,-', html(root), '<div><button>+</button>1<button>-</button></div>');
expect('buttons still the same nodes', find(root, '+') === plusBtn && find(root, '-') === minusBtn, true);

