// Node harness for one message per edit under IME composition. The app
// counts its search messages (tests/apps/controls.roc), and whichever order
// the engine ends a composition in, the committed text reaches the app
// once. tests/check_form.mjs owns the pinning in the same two orders, and
// tests/e2e/controls_test.roc the rest of the fixture.
// Run from the repo root: node tests/check_controls.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, byId, fakeDom, textOf } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('controls')), root, flags: '', dom: fakeDom });
const search = byId(root, 'search');
const searches = () => textOf(byId(root, 'searches'));

expect('no messages yet', searches(), 'searches 0');

// A plain keystroke, for scale.
search.value = 'a';
search.listeners.input({ target: search });
expect('a keystroke is one message', searches(), 'searches 1');

// Chromium's ending: the last input still carries isComposing, then
// compositionend. That input already delivered the committed text.
search.value = 'a日';
search.listeners.input({ target: search, isComposing: true });
search.listeners.compositionend({ target: search });
expect('a composition in Chromium\'s order is one message', searches(), 'searches 2');

// Firefox's ending, and Playwright's fill on Firefox: compositionend with
// the text committed, then one input without isComposing that carries it.
search.value = 'a日本';
search.listeners.compositionend({ target: search });
search.listeners.input({ target: search, isComposing: false });
expect('a composition in Firefox\'s order is one message', searches(), 'searches 3');
expect('the model holds the committed text', search.value, 'a日本');
