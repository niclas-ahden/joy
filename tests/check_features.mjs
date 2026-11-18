// Node harness for browser features: Effect.call reaches the effect
// defined under its id and the answer comes back framed as done, a throwing
// effect comes back as failed with the error's name and message, a sent
// effect runs with its bytes and answers nothing, an id
// this runtime.js was built without fails with a pointer to rebuilding it,
// and Sub.listen's events run exactly while the subscription is in the app's
// list. The effects are defined here, on the runtime the app mounts on,
// the way an app's generated runtime.js defines its features.
// Run from the repo root: node tests/check_features.mjs
import { readFileSync } from 'node:fs';
import { defineSubscription, defineEffect, mount } from '../www/runtime.js';
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
defineEffect('joy/test/echo', (args) => utf8(`said ${text(args.remaining())}`));
defineEffect('joy/test/sent', (args) => { sent = text(args.remaining()); });
defineEffect('joy/test/broken', () => { throw new RangeError('out of range'); });
defineSubscription('joy/test/ticks', (args, host, emit) => {
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
expect('a throwing effect fails with its error', await settled(() => html().includes('broken: failed RangeError: out of range')), true);

find(root, 'Send').listeners.click();
expect('a sent effect runs with its bytes', await settled(() => sent === 'note'), true);

// What the runtime says on the console while the absent effect is called.
const consoleErrors = [];
const realError = console.error;
console.error = (...parts) => consoleErrors.push(parts.join(' '));
find(root, 'Absent').listeners.click();
expect('an effect the runtime lacks says to rebuild it', await settled(() => html().includes('absent: failed MissingEffectError: joy/test/absent is not in this runtime.js')), true);
console.error = realError;
expect('and the console says so, since the app cannot know why', consoleErrors.some((line) => line.includes('joy/test/absent is not in this runtime.js')), true);

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

// --- What a subscription's JavaScript throws is its own trouble ---
// A start that throws, a stop that throws and an async start each say so on
// the console, and the app goes on answering.
{
  const said = [];
  console.error = (...parts) => said.push(parts.join(' '));
  const next = (start) => defineSubscription('joy/test/ticks', start);
  const again = find(root, 'Listen').listeners.click;

  next(() => { throw new TypeError('no such event'); });
  again();
  await tick();
  expect('a start that throws is said by its id', said.some((line) => line.includes('the subscription joy/test/ticks failed to start: TypeError: no such event')), true);
  again();
  await tick();

  next(() => () => { throw new Error('cannot let go'); });
  again();
  await tick();
  again();
  await tick();
  expect('a stop that throws is said too', said.some((line) => line.includes('the subscription joy/test/ticks failed to stop: Error: cannot let go')), true);

  let later = 0;
  next(async (args) => { args.u8(); await tick(); return () => { later++; }; });
  again();
  await tick();
  again();
  expect('an async start is stopped once it has started', await settled(() => later === 1), true);

  find(root, 'Echo').listeners.click();
  expect('and the app goes on', await settled(() => html().includes('echo: ok said hej')), true);
  console.error = realError;
}

// --- What an effect leaves of its arguments is said ---
{
  const warned = [];
  const realWarn = console.warn;
  console.warn = (...parts) => warned.push(parts.join(' '));
  defineEffect('joy/test/sent', () => {});
  find(root, 'Send').listeners.click();
  expect('unread arguments are named with their effect', await settled(() => warned.some((line) => line.includes('joy/test/sent left 4 of the 4 bytes of its arguments unread'))), true);
  console.warn = realWarn;
}

// --- Wire says when the two halves disagree ---
// Each value has its kind in front, so a read of another kind, or past the
// end, fails by name and says which value, where it would have been read as
// some other number.
{
  const { WireReader, WireWriter } = await import('../www/runtime.js');
  const thrown = (run) => { try { run(); return 'nothing'; } catch (err) { return `${err.name}: ${err.message}`; } };
  const disagree = ' The Roc and the JavaScript disagree on what is passed, or on its order.';
  const all = new WireReader(new WireWriter().u8(7).u16(513).u32(70000).u64(9).i64(-5).f64(640.5).bool(true).bytes([9, 8]).str('hej').u16s([0, 500, 1000]).done());
  expect('every kind of value comes back as it was written', JSON.stringify([all.u8(), all.u16(), all.u32(), all.u64(), all.i64(), all.f64(), all.bool(), [...all.bytes()], all.str(), all.u16s()]), '[7,513,70000,9,-5,640.5,true,[9,8],"hej",[0,500,1000]]');
  expect('and nothing is left', all.left(), 0);
  expect('a value of another kind is refused by name and place', thrown(() => { const r = new WireReader(new WireWriter().str('a').f64(640).bool(true).done()); r.str(); r.bool(); }), `WireMismatchError: Value 2 is an f64, where the JavaScript reads a bool.${disagree}`);
  expect('bytes no writer wrote are no value', thrown(() => new WireReader(new Uint8Array([104, 105])).str()), `WireMismatchError: Value 1 is no value a writer wrote, where the JavaScript reads a string.${disagree}`);
  expect('a read past the end says which value', thrown(() => { const r = new WireReader(new WireWriter().u32(7).done()); r.u32(); r.str(); }), `WireEndedError: The bytes ended before value 2, a string.${disagree}`);
  expect('a value that is cut short says where', thrown(() => new WireReader(new Uint8Array([3, 1, 0])).u32()), `WireEndedError: The bytes ended in value 1, a u32: 2 of 3 are left at byte 1.${disagree}`);
  expect('a string longer than what is left is cut short too', thrown(() => new WireReader(new Uint8Array([9, 9, 0, 0, 0, 104])).str()).startsWith('WireEndedError: The bytes ended in value 1, a string: 1 of 6 are left at byte 5.'), true);
  expect('what is left is read as it is', [...new WireReader(new Uint8Array([104, 105])).remaining()].join(','), '104,105');
  expect('a negative u32 is refused', thrown(() => new WireWriter().u32(-1)), 'RangeError: Wire: u32(-1) takes a number from 0 to 4294967295');
  expect('a u8 that is too large is refused', thrown(() => new WireWriter().u8(256)), 'RangeError: Wire: u8(256) takes a number from 0 to 255');
  expect('what is not a number is refused', thrown(() => new WireWriter().u16(NaN)), 'RangeError: Wire: u16(NaN) takes a number from 0 to 65535');
  expect('a fraction is cut, after the tag', new WireWriter().u32(1280.5).done().join(','), '3,0,5,0,0');
}
