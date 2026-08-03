// Node harness for the toggle app: exercises the diff's REPLACE path (a child
// changing kind text<->element) while asserting the unchanged button is reused.
// Run from the repo root: node tests/check_toggle.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync('build/toggle.wasm'), root, flags: '', dom: fakeDom });
const nextBtn = find(root, 'next');
const click = () => nextBtn.listeners.click();

expect('init (even, text child)', html(root), '<div><button>next</button>even 0</div>');
click();
expect('after next (odd, <b> child): REPLACE text->element', html(root), '<div><button>next</button><b>odd 1</b></div>');
click();
expect('after next (even, text child): REPLACE element->text', html(root), '<div><button>next</button>even 2</div>');
expect('button reused across REPLACEs', find(root, 'next') === nextBtn, true);

