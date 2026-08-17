// Node harness for flags: the string passed to mount reaches init as its
// argument, where the built-in Json.parse decodes it into a typed record.
// Run from the repo root: node tests/check_flags.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('flags'));

// Valid JSON flags decode into the model (non-ASCII exercises the big-string path).
const root = new El('#root');
await mount({ wasm: bytes, root, flags: '{"name": "Brödil", "karma": 99}', dom: fakeDom });
expect('name decoded', htmlBare(root).includes('Name: Brödil'), true);
expect('karma decoded', htmlBare(root).includes('Karma: 99'), true);
expect('positive karma judged', htmlBare(root).includes("You're alright!"), true);

// Negative karma takes the other branch.
const grumpy = new El('#root');
await mount({ wasm: bytes, root: grumpy, flags: '{"name": "Ron", "karma": -5}', dom: fakeDom });
expect('negative karma judged', htmlBare(grumpy).includes("Karma isn't real, anyway! Right?"), true);

// No flags: the hint is shown (and update logged the decode failure).
const logged = [];
const realLog = console.log;
console.log = (...a) => logged.push(a.join(' '));
const bare = new El('#root');
await mount({ wasm: bytes, root: bare, flags: '', dom: fakeDom });
console.log = realLog;
expect('no flags -> hint', htmlBare(bare).includes("Let's set some flags!"), true);
expect('decode failure logged', logged.some((l) => l.startsWith('Failed to decode flags')), true);

// Broken JSON: the error view shows the raw flags.
const broken = new El('#root');
console.log = () => {};
await mount({ wasm: bytes, root: broken, flags: '{oops', dom: fakeDom });
console.log = realLog;
expect('broken flags -> error view', htmlBare(broken).includes("we couldn't parse the given flags"), true);
expect('raw flags shown', htmlBare(broken).includes('{oops'), true);

