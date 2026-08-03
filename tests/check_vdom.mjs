// Node harness for the vdom stress app: walks the view through three shapes
// and asserts every diff path: text patched in place, attr add/remove/change,
// boolean attrs driving live form state, handler remove/re-add (exactly one
// dispatch per click, no stale or duplicate listeners), unsafe attributes
// refused, tag changes replacing the node, and unkeyed child-list edits.
// Run from the repo root: node tests/check_vdom.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html, htmlBare, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

const root = new El('#root');
const app = await mount({ wasm: readFileSync('build/vdom.wasm'), root, flags: '', dom: fakeDom });

// All elements matching pred, pre-order.
const collect = (node, pred, out = []) => {
  if (node instanceof El) {
    if (pred(node)) out.push(node);
    for (const c of node.children) collect(c, pred, out);
  }
  return out;
};

const next = () => find(root, 'next').listeners.click();
const clicksShown = () => htmlBare(root).match(/clicks (\d+)/)[1];

// --- Step 0: baseline ---
const pNode = find(root, 'hello');
const pText = pNode.children[0];
const [textInput, checkbox] = collect(root, (n) => n.tag === 'input');
const target = find(root, 'target');
const link = find(root, 'link');
const liOne = find(root, 'one');

expect('p attrs at start', pNode.attrs.get('class') + ',' + pNode.attrs.get('title'), 'alpha,greeting');
expect('value attribute mirrored into the live property', textInput.value, 'v0');
expect('checked attribute mirrored into the live property', checkbox.checked, true);
expect('link href set', link.attrs.get('href'), 'https://example.com');
expect('list at start', htmlBare(root).includes('<ul><li>one</li><li>two</li><li>three</li></ul>'), true);
expect('one click listener bound on target', target.listenerCount('click'), 1);

target.listeners.click();
expect('armed handler dispatches once', clicksShown(), '1');

// Simulate the user typing and unchecking before the next render.
textInput.value = 'user typed';
checkbox.checked = false;

// --- Step 1: attrs change, handler removed, unsafe attrs attempted ---
next();

expect('text patched in place (same <p>)', find(root, 'world') === pNode, true);
expect('text node reused (SET_TEXT)', pNode.children[0] === pText, true);
expect('class changed', pNode.attrs.get('class'), 'beta');
expect('title removed', pNode.attrs.has('title'), false);
expect('new attr added', pNode.attrs.get('data-x'), '1');
expect('on* attribute refused', pNode.attrs.has('onclick'), false);
expect('javascript: href refused (and stale href dropped)', link.attrs.has('href'), false);
expect('removing the value attr clears what the user typed', textInput.value, '');
expect('unchecking via the view clears the live property', checkbox.checked, false);
expect('middle insert in unkeyed list', htmlBare(root).includes('<ul><li>one</li><li>mid</li><li>two</li><li>three</li></ul>'), true);
expect('first li reused across the insert', find(root, 'one') === liOne, true);

target.listeners.click();
expect('removed handler is inert', clicksShown(), '1');
expect('still only one DOM listener on target', target.listenerCount('click'), 1);

// The user re-checks the box before the next render.
checkbox.checked = true;

// --- Step 2: handler re-added, tag change, list shrinks ---
next();

const bNode = find(root, 'world');
expect('tag change replaced the node', bNode !== pNode, true);
expect('replacement is a <b>', bNode.tag, 'b');
expect('value is host-controlled again', textInput.value, 'v2');
expect('checkbox is host-controlled again', checkbox.checked, true);
expect('link href restored', link.attrs.get('href'), 'https://example.com');
expect('list shrank', htmlBare(root).includes('<ul><li>one</li><li>three</li></ul>'), true);
expect('first li survived the removals', find(root, 'one') === liOne, true);
expect('re-added handler did not double-bind', target.listenerCount('click'), 1);

target.listeners.click();
expect('re-added handler dispatches exactly once', clicksShown(), '2');

// --- Unmount: later dispatches must be no-ops ---
const before = html(root);
app.unmount();
find(root, 'next').listeners.click();
expect('dispatch after unmount is a no-op', html(root), before);

