// Node harness for modal: DOM.show_modal/close_modal commands cross as effects, hit
// the dialog matched by the CSS selector, and compose with model updates
// (including an arm that keeps the model unchanged but still runs its effect).
// Run from the repo root: node tests/check_modal.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare, dialogs, modalCalls } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('modal'));

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });

expect('dialog rendered', dialogs.length, 1);
expect('dialog closed initially', !!dialogs[0].open, false);
expect('no modal calls yet', modalCalls.length, 0);

// Open: the model updates AND the dialog opens (paint before effects, so
// the dialog exists/has fresh content when showModal runs).
find(root, 'Delete everything').listeners.click();
expect('show_modal reached the dialog', dialogs[0].open, true);
expect('show call recorded', JSON.stringify(modalCalls[0]), JSON.stringify({ kind: 'show', selector: '#confirm' }));
expect('model updated alongside', htmlBare(root).includes('opened 1, confirmed 0'), true);

// Confirm: closes and counts.
find(root, 'Yes, delete').listeners.click();
expect('close_modal closed the dialog', !!dialogs[0].open, false);
expect('confirm counted', htmlBare(root).includes('opened 1, confirmed 1'), true);

// Dismiss: update keeps the model unchanged, but the close effect still runs.
find(root, 'Delete everything').listeners.click();
expect('reopened', dialogs[0].open, true);
find(root, 'Keep it').listeners.click();
expect('dismiss closed the dialog despite unchanged model', !!dialogs[0].open, false);
expect('dismiss changed no counts', htmlBare(root).includes('opened 2, confirmed 1'), true);

