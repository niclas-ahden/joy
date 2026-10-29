// Node harness for debounce: Time.debounce re-arms the keyed timer on every
// keystroke (only the last of a burst fires, with the final model state),
// Time.cancel discards a pending timer, and a pending timer at unmount is
// released without re-entering the dead instance, also when the instance
// trapped first. Uses real timers: the example debounces at 200ms, the test
// waits 350ms.
// Run from the repo root: node tests/check_debounce.mjs
import { readFileSync } from 'node:fs';
import { El, fakeDom, find, findTag, htmlBare } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { makeRuntime, mount } = await appRuntime('debounce');

const bytes = readFileSync(wasmPath('debounce'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const root = new El('#root');
const app = await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const input = findTag(root, 'input');
const type = (s) => { input.value = s; input.listeners.input({ target: input }); };

// A burst of keystrokes: only one search fires, with the final text.
type('j');
type('jo');
type('joy');
expect('nothing fires while typing', htmlBare(root).includes('searches: 0'), true);
await sleep(350);
expect('one search after the pause', htmlBare(root).includes('searches: 1'), true);
expect('searched with the final text', htmlBare(root).includes('searched for: joy'), true);

// A second burst works the same (the key is reusable).
type('joy!');
await sleep(350);
expect('second burst fired once', htmlBare(root).includes('searches: 2'), true);
expect('second text landed', htmlBare(root).includes('searched for: joy!'), true);

// Cancel discards the pending timer: no search ever fires.
type('never');
find(root, 'Cancel').listeners.click();
await sleep(350);
expect('canceled timer never fired', htmlBare(root).includes('searches: 2'), true);
expect('cancel with nothing pending is a no-op', (find(root, 'Cancel').listeners.click(), true), true);

// A pending timer at unmount is cleaned up and must not re-enter wasm.
type('goodbye');
const frozen = htmlBare(root);
app.unmount();
await sleep(350);
expect('pending debounce after unmount is a no-op', htmlBare(root), frozen);
expect('no deallocs missed', app.instance.exports.dealloc_miss(), 0);

// A trap leaves the instance unable to take any call, because its stack
// pointer stays wrapped and the next call that touches the stack traps
// again. Modeled with exports that all throw once the fault is armed. A
// debounce pending at the trap must not stop unmount from finishing.
{
  const { instance } = await WebAssembly.instantiate(bytes, {});
  let trapped = false;
  const exports = {};
  for (const [name, value] of Object.entries(instance.exports)) {
    exports[name] = typeof value !== 'function' ? value : (...args) => {
      if (trapped) throw new WebAssembly.RuntimeError('memory access out of bounds');
      return value(...args);
    };
  }
  const root2 = new El('#root');
  const rt = makeRuntime(exports, fakeDom, root2);
  rt.start('');
  const input2 = findTag(root2, 'input');
  input2.value = 'doomed';
  input2.listeners.input({ target: input2 });
  trapped = true;
  let crash = null;
  try {
    find(root2, 'Cancel').listeners.click();
  } catch (err) {
    crash = err.message;
  }
  expect('the click traps', crash?.startsWith('Joy: the app crashed'), true);
  const frozen2 = htmlBare(root2);
  let unmounted = 'ok';
  try {
    rt.unmount();
  } catch (err) {
    unmounted = String(err);
  }
  expect('unmount after a trap finishes', unmounted, 'ok');
  await sleep(350);
  expect('pending debounce after a trap is a no-op', htmlBare(root2), frozen2);
}
