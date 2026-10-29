// Node harness for DOM.focus: the effect crosses the host, runs after the
// paint (so it can focus an element the same update just rendered), and a
// selector that matches nothing is a no-op. The fake DOM records the calls
// and a stand-in for document.activeElement.
// Run from the repo root: node tests/check_focus.mjs
import { readFileSync } from 'node:fs';
import { El, fakeDom, find, findTag, focused, focusCalls, htmlBare } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('focus');

const bytes = readFileSync(wasmPath('focus'));

// A selector that matches nothing is a no-op that warns, so the warnings
// are collected: none for a hit, one for a miss.
const warns = [];
const realWarn = console.warn;
console.warn = (...args) => { warns.push(args.join(' ')); };
process.on('exit', () => { console.warn = realWarn; });

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });

expect('no input before editing', findTag(root, 'input'), null);
expect('no focus calls yet', focusCalls.length, 0);
expect('nothing focused yet', focused.el, null);

// Edit: the input appears in this render AND receives focus, which only
// works because the paint precedes the effects.
find(root, 'Edit').listeners.click();
const input = findTag(root, 'input');
expect('editor rendered', input !== null, true);
expect('focus call recorded', JSON.stringify(focusCalls), JSON.stringify(['#name']));
expect('focus landed on the new input', focused.el, input);
expect('a hit does not warn', warns.length, 0);
expect('input starts from the model', input.attrs.get('value'), 'Ada');

// The focused input is live: typing updates the model.
input.listeners.input({ target: { value: 'Grace' } });
expect('typed text reached the model', htmlBare(root).includes('Hello, Grace'), true);
find(root, 'Done').listeners.click();
expect('editor closed', findTag(root, 'input'), null);

// A selector that matches nothing: the model still updates, focus stays put.
find(root, 'Focus nothing').listeners.click();
expect('missing selector was attempted', focusCalls.at(-1), '#nope');
expect('missing selector changed nothing', focused.el, input);
expect('model updated alongside the no-op', htmlBare(root).includes('missing 1'), true);
expect('a miss warns once', warns.length, 1);
expect('the warning names the effect and selector', warns[0].includes('DOM.focus') && warns[0].includes('"#nope"'), true);
