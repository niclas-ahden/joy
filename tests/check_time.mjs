// Node harness for time: a Time.every subscription declared by
// `subscriptions` drives typed Tick(I64) msgs; calming down drops the
// subscription from the list, which must stop the interval, and getting
// excited again must start a fresh one. Remembered moments reuse the time the
// last tick delivered. Run from the repo root: node tests/check_time.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

// Deterministic clock + captured intervals.
const T0 = 1_751_450_000_000;
let nowMs = T0;
const realNow = Date.now;
Date.now = () => nowMs;
const intervals = [];
const cleared = [];
const realSetInterval = globalThis.setInterval;
const realClearInterval = globalThis.clearInterval;
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = (id) => { cleared.push(id); };

// The example expects the boot clock in the flags string (init is pure and
// has no clock), so pass T0 the way a browser embedder passes Date.now().
const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('time')), root, flags: String(T0), dom: fakeDom });

expect('one interval started from the subscription', intervals.length, 1);
expect('interval period', intervals[0].ms, 1000);
expect('initial level', find(root, 'Your excitement level for Roc: 0') !== null, true);

// Three seconds pass, but only one tick fires: the level counts ticks, not
// wall clock seconds, which is what makes pausing hold it still below.
nowMs = T0 + 3000;
intervals[0].fn();
expect('level after tick', find(root, 'Your excitement level for Roc: 1') !== null, true);

// Remember a moment: pure update reuses the time carried by the last Tick
// msg, so a click between ticks records the tick's time, not the click's.
nowMs = T0 + 3500;
find(root, 'Remember this moment').listeners.click();
expect(
  'remembered moment shows the last tick time',
  find(root, `Level 1, reached at ${T0 + 3000}`) !== null,
  true,
);

nowMs = T0 + 5000;
intervals[0].fn();
expect('level keeps climbing', find(root, 'Your excitement level for Roc: 2') !== null, true);
expect('remembered moment preserved', find(root, `Level 1, reached at ${T0 + 3000}`) !== null, true);

// Calm down: the subscription leaves the declared list; the host must stop
// the interval (cancellation by omission).
find(root, 'Calm down').listeners.click();
expect('calming down clears the interval', cleared.length, 1);

// A late fire from the (now cleared) interval is a no-op host-side too.
nowMs = T0 + 7000;
intervals[0].fn();
expect('no tick while paused', find(root, 'Your excitement level for Roc: 2') !== null, true);

// Getting excited again: re-declaring the subscription starts a fresh
// interval.
find(root, 'Get excited!').listeners.click();
expect('resume starts a new interval', intervals.length, 2);
expect('resumed period', intervals[1].ms, 1000);
nowMs = T0 + 9000;
intervals[1].fn();
expect('ticks again after resume', find(root, 'Your excitement level for Roc: 3') !== null, true);

Date.now = realNow;
globalThis.setInterval = realSetInterval;
globalThis.clearInterval = realClearInterval;
