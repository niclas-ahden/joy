// Node harness for crashes: what a `crash` in Roc code says is in the error
// the runtime throws, whether the app crashes while starting or on a message,
// and the app stays stopped after it.
// Run from the repo root: node tests/check_crash.mjs
import { readFileSync } from 'node:fs';
import { El, fakeDom, find } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('crash');
const wasm = readFileSync(wasmPath('crash'));
const stopped = 'Joy: the app crashed and has stopped. It said: ';

const starting = await mount({ wasm, root: new El('#root'), flags: 'crash in init', dom: fakeDom }).then(() => 'mounted', (err) => err);
expect('a crash in init says what the app said', starting.message, `${stopped}Could not read the flags: crash in init`);
expect('a crash in init keeps the trap as its cause', starting.cause instanceof WebAssembly.RuntimeError, true);

// What a click throws, or 'nothing'.
const click = (root, label) => {
  try {
    find(root, label).listeners.click();
    return 'nothing';
  } catch (err) {
    return err.message;
  }
};

{
  const root = new El('#root');
  await mount({ wasm, root, flags: '', dom: fakeDom });
  expect('a crash in update says what the app said', click(root, 'Long'), `${stopped}Brödil has no karma left, and that should never happen`);
  expect('the app stays stopped', click(root, 'Long'), 'nothing');
}

{
  const root = new El('#root');
  await mount({ wasm, root, flags: '', dom: fakeDom });
  expect('a short text is kept too', click(root, 'Short'), `${stopped}No`);
}
