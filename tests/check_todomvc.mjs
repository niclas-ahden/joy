// Node harness for todomvc: a smoke pass over the app logic on the fake DOM.
// Adding (with trimming), toggling, editing and clearing, plus the empty
// state where the list section and footer do not exist. The full behaviour
// lives in the example's own browser suite, examples/todomvc/tests/.
// Run from the repo root: node tests/check_todomvc.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

// All elements carrying the class, pre-order.
const byClass = (node, cls, out = []) => {
  if (node instanceof El) {
    if ((node.attrs.get('class') ?? '').split(' ').includes(cls)) out.push(node);
    for (const c of node.children) c instanceof El && byClass(c, cls, out);
  }
  return out;
};
const one = (cls) => byClass(root, cls)[0];

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('todomvc')), root, flags: '', dom: fakeDom });

// The list section and footer only exist while there are todos.
expect('starts without a list section', byClass(root, 'main').length, 0);
expect('starts without a footer', byClass(root, 'footer').length, 0);

// A user types into the new-todo input and presses Enter. Re-query after the
// input event: the render it triggers may patch the node.
const add = (title) => {
  one('new-todo').listeners.input({ target: { value: title } });
  one('new-todo').listeners.keydown({ key: 'Enter', preventDefault: () => {} });
};

add('  Buy milk  ');
expect('todo added', byClass(root, 'todo-list')[0].children.length, 1);
expect('title trimmed', one('todo-list').children[0].children[0].children[1].children[0].text, 'Buy milk');
expect('count is singular', html(one('todo-count')), '<strong>1</strong> item left');
expect('input cleared for the next todo', one('new-todo').value ?? '', '');

add('Walk the dog');
expect('both todos listed', one('todo-list').children.length, 2);
expect('count is plural', html(one('todo-count')), '<strong>2</strong> items left');

// Toggle the first todo through its checkbox's change event.
const toggle = one('toggle');
toggle.checked = true;
toggle.listeners.change({ target: toggle });
expect('toggled todo completed', byClass(root, 'completed').length, 1);
expect('count follows', html(one('todo-count')), '<strong>1</strong> item left');

// Edit the second todo: dblclick its label, retype, commit with Enter.
one('todo-list').children[1].children[0].children[1].listeners.dblclick({});
expect('row enters editing', byClass(root, 'editing').length, 1);
const edit = byClass(one('todo-list').children[1], 'edit')[0];
expect('edit starts from the title', edit.attrs.get('value'), 'Walk the dog');
edit.listeners.input({ target: { value: 'Walk the cat' } });
byClass(one('todo-list').children[1], 'edit')[0].listeners.keydown({ key: 'Enter', preventDefault: () => {} });
expect('editing ends', byClass(root, 'editing').length, 0);
expect('edit committed', one('todo-list').children[1].children[0].children[1].children[0].text, 'Walk the cat');

// Clear completed drops the toggled todo and the button with it.
one('clear-completed').listeners.click();
expect('completed todo cleared', one('todo-list').children.length, 1);
expect('clear button gone', byClass(root, 'clear-completed').length, 0);

// Destroying the last todo brings the empty state back.
one('destroy').listeners.click();
expect('list section gone again', byClass(root, 'main').length, 0);
expect('footer gone again', byClass(root, 'footer').length, 0);
