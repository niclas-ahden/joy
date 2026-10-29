// Node harness for keyed_list: children with `key` attributes keep their
// identity across reorders, inserts and removals: the differ moves the
// existing DOM nodes instead of rebuilding them, each step costs exactly the
// moves, inserts or removals it names, and no `key` attribute ever reaches
// the DOM.
// Run from the repo root: node tests/check_keyed_list.mjs
import { readFileSync } from 'node:fs';
import { El, byRole, findTag, htmlBare } from './fakedom.mjs';
import { appRuntime, countingDom, expect, meter, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('keyed_list');

const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('keyed_list')), root, flags: '', dom: counted.dom });
const work = meter(app, counted);

const ul = findTag(root, 'ul');
const labels = () => ul.children.map((li) => li.children[0].text);
const click = (label) => { work.mark(); byRole(root, 'button', label).listeners.click(); };
// Every step is one REORDER and never a REPLACE: the list is patched, not
// rebuilt.
const budget = (label, want) => work.expectDelta(label, { patchReorder: 1, patchReplace: 0, ...want });

expect('initial order', labels().join(','), 'apple,banana,cherry,date');
expect('key is not a DOM attribute', ul.children[0].attrs.has('key'), false);

// Rotate: apple moves to the end; every li node object survives.
const [apple, banana, cherry, date] = ul.children;
click('rotate');
expect('rotated order', labels().join(','), 'banana,cherry,date,apple');
expect('ul reused', findTag(root, 'ul') === ul, true);
expect('moved node reused', ul.children[3] === apple, true);
expect('stayed nodes reused', ul.children[0] === banana && ul.children[1] === cherry && ul.children[2] === date, true);
expect('text node reused inside moved li', apple.children[0].text, 'apple');
budget('rotate moves one node', { moves: 1, inserts: 0, removals: 0, elements: 0 });

// Prepend: one fresh node in front, existing nodes untouched.
click('prepend');
expect('prepended order', labels().join(','), 'new 1,banana,cherry,date,apple');
expect('existing nodes reused after prepend', ul.children[1] === banana && ul.children[4] === apple, true);
budget('prepend builds one li', { elements: 1, textNodes: 1, inserts: 1, moves: 0, removals: 0 });
const fresh = ul.children[0];

// Remove the second item (banana); everything else keeps its identity.
click('remove second');
expect('removed order', labels().join(','), 'new 1,cherry,date,apple');
expect('nodes reused after removal', ul.children[0] === fresh && ul.children[1] === cherry && ul.children[3] === apple, true);
expect('removed node detached', banana.parent, null);
budget('removal detaches one node', { removals: 1, moves: 0, inserts: 0, elements: 0 });

// Several ops in a row still converge to the right structure.
click('rotate'); // cherry,date,apple,new 1
click('rotate'); // date,apple,new 1,cherry
expect('structure after more rotates', labels().join(','), 'date,apple,new 1,cherry');
expect('full html sane', htmlBare(root).includes('<ul><li>date</li><li>apple</li><li>new 1</li><li>cherry</li></ul>'), true);

// Reverse is the LIS worst case, where every node moves and every node survives.
click('reverse');
expect('reversed order', labels().join(','), 'cherry,new 1,apple,date');
expect('all nodes reused through a full reverse', ul.children[0] === cherry && ul.children[1] === fresh && ul.children[2] === apple && ul.children[3] === date, true);
// One node of n can stay put (the LIS of a reversal has length 1).
budget('reverse moves all but one', { moves: 3, inserts: 0, removals: 0, elements: 0 });

// Reverse + prepend + remove in sequence keeps identity and order coherent.
click('prepend'); // new 2,cherry,new 1,apple,date
click('reverse'); // date,apple,new 1,cherry,new 2
expect('mixed prepend/reverse order', labels().join(','), 'date,apple,new 1,cherry,new 2');
expect('old nodes still reused', ul.children[0] === date && ul.children[2] === fresh, true);
budget('reverse of five moves four', { moves: 4, elements: 0 });
click('remove second'); // date,new 1,cherry,new 2
expect('final structure', labels().join(','), 'date,new 1,cherry,new 2');
expect('apple detached after removal', apple.parent, null);
