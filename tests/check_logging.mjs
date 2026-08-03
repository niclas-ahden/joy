// Node harness for logging: the two console streams stay separate all the
// way through the host queue. Console.log effects drain to console.log and
// `dbg` statements drain to console.debug, each on the entry call that
// produced them.
// Run from the repo root: node tests/check_logging.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

const logged = [];
const debugged = [];
const realLog = console.log;
const realDebug = console.debug;
console.log = (...a) => logged.push(a.join(' '));
console.debug = (...a) => debugged.push(a.join(' '));

const root = new El('#root');
await mount({ wasm: readFileSync('build/logging.wasm'), root, flags: '', dom: fakeDom });

expect('boot Console.log drained to console.log', logged.length, 1);
expect('boot message intact', logged[0], 'The app booted');
expect('no dbg at boot', debugged.length, 0);

find(root, 'Click me').listeners.click();

expect('click Console.log drained to console.log', logged.length, 2);
expect('click message intact', logged[1], 'Clicked 1 times');
// The dbg statement in update fires once per click. Its exact rendering
// belongs to the compiler (the inspected value), so only pin the payload.
expect('dbg drained to console.debug', debugged.length, 1);
expect('dbg carries the inspected value', debugged[0].includes('clicks'), true);
expect('dbg did not leak into console.log', logged.some((l) => l.includes('clicks:')), false);

find(root, 'Click me').listeners.click();

expect('second click logs again', logged[2], 'Clicked 2 times');
expect('second dbg arrives', debugged.length, 2);

console.log = realLog;
console.debug = realDebug;
