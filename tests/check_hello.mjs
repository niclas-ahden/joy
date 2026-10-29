// Node harness for hello: static render, no events.
// Run from the repo root: node tests/check_hello.mjs
import { readFileSync } from 'node:fs';
import { El, fakeDom, html } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('hello');

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('hello')), root, flags: '', dom: fakeDom });

expect('hello renders', html(root), '<div>Hello, Roc!</div>');
