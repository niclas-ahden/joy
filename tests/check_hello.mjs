// Node harness for hello: static render, no events.
// Run from the repo root: node tests/check_hello.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html } from './fakedom.mjs';
import { expect } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync('build/hello.wasm'), root, flags: '', dom: fakeDom });

expect('hello renders', html(root), '<div>Hello, Roc!</div>');
