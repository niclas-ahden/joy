// Node harness for events_input: a value-carrying `on_input` event calls the
// app's boxed Str -> Msg decoder, and the Console.log command reaches the console.
// Run from the repo root: node tests/check_events_input.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, findTag, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

// All elements matching pred, pre-order.
const collect = (node, pred, out = []) => {
  if (node instanceof El) {
    if (pred(node)) out.push(node);
    for (const c of node.children) collect(c, pred, out);
  }
  return out;
};

// Spy on console.log to assert the Console.log command round trip.
const logged = [];
const realLog = console.log;
console.log = (...args) => { logged.push(args.join(' ')); };

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('events_input')), root, flags: '', dom: fakeDom });
console.log = realLog;

expect('heading rendered', find(root, 'Dear diary') !== null, true);
const ta = findTag(root, 'textarea');
expect('textarea attrs', `${ta.attrs.get('rows')},${ta.attrs.get('cols')}`, '10,30');

// Fire input events with values; the boxed decoder turns them into Msgs.
console.log = (...args) => { logged.push(args.join(' ')); };
ta.listeners.input({ target: { value: 'Hello diary' } });
console.log = realLog;
const p = findTag(root, 'p');
expect('typed text rendered', p.children[0]?.text, 'Hello diary');
expect('Console.log drained to console', logged.includes('User typed: Hello diary'), true);

// A second input replaces the first (update returns the new string).
console.log = (...args) => { logged.push(args.join(' ')); };
ta.listeners.input({ target: { value: 'Dear diary, today I crossed the boundary — twice! ✨' } });
console.log = realLog;
expect('long/unicode value round-trips', findTag(root, 'p').children[0]?.text, 'Dear diary, today I crossed the boundary — twice! ✨');

// on_submit: the msg dispatches AND the browser default (page reload) is
// suppressed, whether submission came from Enter or the submit button.
const formEl = findTag(root, 'form');
let defaultPrevented = 0;
formEl.listeners.submit({ preventDefault: () => { defaultPrevented += 1; } });
expect('on_submit prevented the page reload', defaultPrevented, 1);
expect('on_submit dispatched the msg', htmlBare(root).includes('Saved: Dear diary, today I crossed the boundary — twice! ✨'), true);

// on_check: the change event delivers the checkbox's live checked state as a
// typed Bool, and the view re-renders from it.
const cb = collect(root, (n) => n.tag === 'input' && n.attrs.get('type') === 'checkbox')[0];
expect('checkbox starts unchecked', cb.checked ?? false, false);
cb.checked = true;
cb.listeners.change({ target: cb });
expect('on_check delivered true', htmlBare(root).includes('Secret (on)'), true);
cb.checked = false;
cb.listeners.change({ target: cb });
expect('on_check delivered false', htmlBare(root).includes('Secret (off)'), true);

