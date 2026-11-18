// Node harness for calls into the app that arrive while one is in progress.
// A page answers a port from inside the handler of the send that asked, the
// way a read from localStorage does, and a script calls in while the view is
// painted, the way a custom element's connectedCallback does. Each waits its
// turn, so the subscriptions an update starts and stops stay its own and a
// paint is never written over.
// Run from the repo root: node tests/check_port_answer.mjs
import { readFileSync } from 'node:fs';
import { El, fakeDom, htmlBare } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('port_answer');

// --- An answer from inside the port handler ---

const root = new El('#root');
const app = await mount({
  wasm: readFileSync(wasmPath('port_answer')),
  root,
  flags: '',
  dom: fakeDom,
  setup: (a) => a.onPort('ask', () => a.sendPort('answer', '')),
});

app.sendPort('x', 'one');
expect('x is heard before the question', htmlBare(root).includes('phase 0 log x:one'), true);

app.sendPort('go', '');
expect('the answer arrived by the time the question returns', htmlBare(root).includes('phase 2'), true);

app.sendPort('y', 'two');
expect('y, subscribed by the answer, is heard', htmlBare(root).includes('log x:one y:two'), true);

app.sendPort('x', 'stale');
expect('x, dropped by the question, is heard no more', htmlBare(root).endsWith('log x:one y:two</div>'), true);

// --- A call while the view is painted ---

// The page sends `go` from inside the paint of an x. The paint finishes
// first, then the question and its answer run.
let during = null;
const callingDom = {
  ...fakeDom,
  setText: (node, value) => {
    if (during) {
      const call = during;
      during = null;
      call();
    }
    return fakeDom.setText(node, value);
  },
};
const root2 = new El('#root2');
const app2 = await mount({
  wasm: readFileSync(wasmPath('port_answer')),
  root: root2,
  flags: '',
  dom: callingDom,
  setup: (a) => a.onPort('ask', () => a.sendPort('answer', '')),
});
during = () => app2.sendPort('go', '');
app2.sendPort('x', 'one');
expect('the call made during the paint was not lost', during, null);
expect('the paint it arrived in finished, and its own followed', htmlBare(root2).includes('phase 2 log x:one'), true);
app2.sendPort('y', 'two');
expect('the page matches the model afterwards', htmlBare(root2).includes('phase 2 log x:one y:two'), true);
