// Node harness for browser features: Effect.call reaches the operation
// defined under its id and the answer comes back framed as done, a throwing
// operation comes back as failed with the error's name and message, a sent
// operation runs with its bytes and answers nothing, an id
// this runtime.js was built without fails with a pointer to rebuilding it,
// and Sub.listen's events run exactly while the subscription is in the app's
// list. The operations are defined here, on the runtime the app mounts on,
// the way an app's generated runtime.js defines its features.
// Run from the repo root: node tests/check_features.mjs
import { readFileSync } from 'node:fs';
import { defineEvents, defineOperation, mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('features'));
const tick = () => new Promise((r) => setTimeout(r, 0));
const settled = async (pred) => {
  for (let i = 0; i < 500 && !pred(); i++) await tick();
  return pred();
};

let emitTick = null;
let stops = 0;
const text = (bytes) => new TextDecoder().decode(bytes);
const utf8 = (s) => new TextEncoder().encode(s);
let sent = null;
defineOperation('joy/test/echo', (args) => utf8(`said ${text(args.remaining())}`));
defineOperation('joy/test/sent', (args) => { sent = text(args.remaining()); });
defineOperation('joy/test/broken', () => { throw new RangeError('out of range'); });
defineEvents('joy/test/ticks', (args, host, emit) => {
  expect('listen gets its args', args.u8(), 5);
  emitTick = emit;
  return () => { stops++; };
});

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const html = () => htmlBare(root);

find(root, 'Echo').listeners.click();
expect('a call answers through its reply', await settled(() => html().includes('echo: ok said hej')), true);

find(root, 'Broken').listeners.click();
expect('a throwing operation fails with its error', await settled(() => html().includes('broken: failed RangeError: out of range')), true);

find(root, 'Send').listeners.click();
expect('a sent operation runs with its bytes', await settled(() => sent === 'note'), true);

find(root, 'Absent').listeners.click();
expect('an operation the runtime lacks says to rebuild it', await settled(() => html().includes('absent: failed NotSupportedError: joy/test/absent is not in this runtime.js')), true);

find(root, 'Listen').listeners.click();
expect('listening starts the events', await settled(() => emitTick !== null), true);
emitTick(utf8('one'));
emitTick(utf8('two'));
expect('events reach update in order', await settled(() => html().includes('events: one,two')), true);

find(root, 'Listen').listeners.click();
await tick();
expect('leaving the list stops the events', stops, 1);
emitTick(utf8('three'));
await tick();
expect('a stopped listen delivers nothing', html().includes('events: one,two,three'), false);
