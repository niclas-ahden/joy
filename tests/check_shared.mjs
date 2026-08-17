// Node harness for the shared app: the model holds a retained Html chunk, so
// renders that leave it alone hand the differ the same value and the
// shared-subtree shortcut skips it wholesale. The skip is observable because
// handler-carrying elements are otherwise re-patched every render (attr_eq
// treats events as never equal), which re-sets their plain attrs too: a
// diffed chunk button gets a setAttr("class", ...) per render, a skipped one
// gets none. Also asserts the chunk's handler stays live across skipped
// renders (the shared subtree survives the previous trees being dropped) and
// that rebuilding the chunk rediffs it normally.
// Run from the repo root: node tests/check_shared.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare, find } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const attrWrites = new Map();
const countingDom = {
  ...fakeDom,
  setAttr: (node, k, v) => {
    attrWrites.set(node, (attrWrites.get(node) ?? 0) + 1);
    fakeDom.setAttr(node, k, v);
  },
};

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('shared')), root, flags: '', dom: countingDom });

const bump = find(root, 'bump');
const grow = find(root, 'grow');
const chunkBtn = find(root, 'chunk');
const clicksShown = () => htmlBare(root).match(/clicks (\d+)/)[1];

expect('initial rows', htmlBare(root).includes('<ul><li>row 1</li><li>row 2</li><li>row 3</li></ul>'), true);
expect('initial clicks', clicksShown(), '0');

const writesAtMount = attrWrites.get(chunkBtn) ?? 0;
bump.listeners.click();
expect('bump re-renders the counter', clicksShown(), '1');
expect('chunk skipped: no attr writes on its button', attrWrites.get(chunkBtn) ?? 0, writesAtMount);
expect('chunk button node reused across the skip', find(root, 'chunk') === chunkBtn, true);

// The handler inside the chunk keeps dispatching after many skipped renders.
for (let i = 0; i < 10; i++) bump.listeners.click();
chunkBtn.listeners.click();
expect('shared handler dispatches after skips', clicksShown(), '12');

// Growing rebuilds the chunk: a fresh value, so the differ descends normally.
grow.listeners.click();
expect('grow rebuilds the chunk', htmlBare(root).includes('<li>row 4</li>'), true);
expect('chunk button patched in place on rebuild', find(root, 'chunk') === chunkBtn, true);

// The freshly rebuilt chunk is retained again, so skipping resumes.
const writesAfterGrow = attrWrites.get(chunkBtn) ?? 0;
bump.listeners.click();
expect('skip resumes after rebuild', attrWrites.get(chunkBtn) ?? 0, writesAfterGrow);
expect('counter still live', clicksShown(), '13');
