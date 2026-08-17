// Node harness for keyboard: global key subscriptions (two identical
// all-keys subs that share one document listener yet both deliver, plus an
// Escape-filtered, default-suppressed one) arrive through document-level
// listeners the host starts and stops as the declared subscription set
// changes; each firing carries the full KeyEvent record (key, physical
// code, modifiers, repeat). The input element's own on_keydown delivers the
// record only to that element's handler, and a keys-filtered element
// handler fires (and prevents the default) only for its listed keys.
// Run from the repo root: node tests/check_keyboard.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, findTag, activeGlobalListeners } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('keyboard')), root, flags: '', dom: fakeDom });

// Two document listeners: ONE shared by the two identical all-keys subs,
// plus the Escape filter.
expect('duplicate subs share a listener (2 total)', activeGlobalListeners().length, 2);
expect('both are keydown', activeGlobalListeners().every((l) => l.event === 'keydown'), true);

const fireGlobal = (event) => {
  let prevented = 0;
  const e = { ...event, preventDefault: () => { prevented += 1; } };
  // Fire on a snapshot: a listener's own dispatch may change the set.
  for (const l of activeGlobalListeners()) l.fn(e);
  return prevented;
};

// A plain key reaches both all-keys subs (fan-out: description AND counter
// from one event); the Escape filter drops it in JS, so no preventDefault.
let prevented = fireGlobal({ key: 'a', code: 'KeyA' });
expect('key and code shown', find(root, 'Last key: a (KeyA)') !== null, true);
expect('duplicate sub fired too', find(root, 'Keys seen: 1') !== null, true);
expect('escape counter untouched', find(root, 'Escapes: 0') !== null, true);
expect('no preventDefault for a plain key', prevented, 0);

// Modifiers and repeat cross as flags on the record.
fireGlobal({ key: 'S', code: 'KeyS', ctrlKey: true, shiftKey: true });
expect('modifiers shown', find(root, 'Last key: S (KeyS) ctrl shift') !== null, true);
fireGlobal({ key: 'x', code: 'KeyX', altKey: true, metaKey: true, repeat: true });
expect('alt/meta/repeat shown', find(root, 'Last key: x (KeyX) alt meta repeat') !== null, true);
expect('both events counted once each', find(root, 'Keys seen: 3') !== null, true);

// IME composition keystrokes cross as the is_composing flag.
fireGlobal({ key: 'Process', code: 'KeyQ', isComposing: true });
expect('composition flag shown', find(root, 'Last key: Process (KeyQ) composing') !== null, true);

// Escape reaches all three subs, and the filtered one suppresses the default.
prevented = fireGlobal({ key: 'Escape', code: 'Escape' });
expect('escape counted', find(root, 'Escapes: 1') !== null, true);
expect('escape shown as last key', find(root, 'Last key: Escape (Escape)') !== null, true);
expect('preventDefault ran for Escape', prevented, 1);

// The input's own key event: fires the element handler only, with the record.
findTag(root, 'input').listeners.keydown({ key: 'Enter', code: 'Enter' });
expect('element key handler got the key', find(root, 'Input key: Enter') !== null, true);
expect('global last key unchanged by element event', find(root, 'Last key: Escape (Escape)') !== null, true);

// The second input filters for Enter with preventDefault: other keys pass
// through untouched (no msg, no preventDefault), Enter is captured and
// suppressed.
const inputs = [];
(function collect(n) {
  if (n.tag === 'input') inputs.push(n);
  for (const c of n.children ?? []) collect(c);
})(root);
const filtered = inputs[1];
let elPrevented = 0;
const fireOn = (key) => filtered.listeners.keydown({ key, code: key, preventDefault: () => { elPrevented += 1; } });
fireOn('a');
expect('non-matching key ignored by filtered handler', find(root, 'Submits: 0') !== null, true);
expect('no preventDefault for non-matching key', elPrevented, 0);
fireOn('Enter');
expect('matching key delivered', find(root, 'Submits: 1') !== null, true);
expect('preventDefault ran for matching key', elPrevented, 1);
expect('input key unchanged by filtered input', find(root, 'Input key: Enter') !== null, true);

// Dropping the subscriptions removes the document listeners...
find(root, 'Stop listening').listeners.click();
expect('listeners removed on stop', activeGlobalListeners().length, 0);
fireGlobal({ key: 'z', code: 'KeyZ' });
expect('no delivery while stopped', find(root, 'Last key: Escape (Escape)') !== null, true);

// ...and re-declaring them registers fresh ones, fan-out intact.
find(root, 'Listen').listeners.click();
expect('listeners re-registered', activeGlobalListeners().length, 2);
fireGlobal({ key: 'z', code: 'KeyZ' });
expect('delivery resumes', find(root, 'Last key: z (KeyZ)') !== null, true);
expect('duplicate sub resumed too', find(root, 'Keys seen: 6') !== null, true);

