// Node harness for ports, both directions: Port.listen registers a named
// decoder at init and JavaScript drives the app through sendPort; Port.send
// commands deliver values to the handlers JavaScript registered with onPort
// (registered via mount's setup hook, in time for sends from init).
// Run from the repo root: node tests/check_ports.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare } from './fakedom.mjs';
import { expect } from './harness.mjs';

const logged = [];
const realLog = console.log;

const statuses = [];
const levels = [];
const root = new El('#root');
const app = await mount({
  wasm: readFileSync('build/ports.wasm'),
  root,
  flags: '',
  dom: fakeDom,
  setup: (a) => {
    a.onPort('status', (v) => statuses.push(v));
    a.onPort('level', (v) => levels.push(v));
  },
});

expect('initial hint rendered', htmlBare(root).includes('app.sendPort'), true);
expect('init sent on the status port', statuses.join(','), 'listening');

console.log = (...a) => logged.push(a.join(' '));
app.sendPort('excitement', '');
app.sendPort('excitement', '');
app.sendPort('excitement', '');
app.sendPort('nobody-listens-here', 'ignored');
console.log = realLog;

expect('three ticks arrived', htmlBare(root).includes('Your excitement level for Roc: 3'), true);
expect('update logged each tick via the ConsoleLog command', logged.includes('Time passes slowly now... 1'), true);
expect('unknown port is a no-op', htmlBare(root).includes('Roc: 3'), true);
expect('each tick sent on the level port', levels.join(','), '1,2,3');

// Stop by omission: at level 3 the subscription leaves the list, so the
// port registration is torn down and a further send doesn't tick.
app.sendPort('excitement', '');
expect('send after cap is a no-op', htmlBare(root).includes('Roc: 3'), true);
expect('no level sent after cap', levels.join(','), '1,2,3');

// Sends after unmount are a no-op (the port registration is torn down).
app.unmount();
app.sendPort('excitement', '');
expect('send after unmount is a no-op', htmlBare(root).includes('Roc: 3'), true);
expect('no level sent after unmount', levels.join(','), '1,2,3');

// Sending to a name with no JS handler must be a no-op (the app also sends
// to "status", which stays registered, so unregister nothing: just assert
// nothing else arrived).
expect('no stray outgoing values', statuses.length, 1);

