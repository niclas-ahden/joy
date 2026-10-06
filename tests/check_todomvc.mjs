// Node harness for spa-todomvc: a smoke pass over the app logic on the fake DOM.
// Adding (with trimming), toggling, editing and clearing, plus the empty
// state where the list section and footer do not exist. Each step also
// carries a work budget: what it built, moved and removed, and which patch
// ops the differ emitted, so a change that keeps the page looking right but
// rebuilds the list to get there fails here. The full behaviour lives in the
// example's own browser suite, examples/spa-todomvc/tests/.
// Run from the repo root: node tests/check_todomvc.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, byClass, byClassAll, byLabel, byRole, byRoleAll, find, html, textOf } from './fakedom.mjs';
import { countingDom, expect, meter, wasmPath } from './harness.mjs';

const counted = countingDom();
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('spa-todomvc')), root, flags: '', dom: counted.dom });
const work = meter(app, counted);

const rows = () => byRoleAll(byClass(root, 'todo-list') ?? root, 'listitem');
const count = () => html(byClass(root, 'todo-count'));

// The list section and footer only exist while there are todos.
expect('starts without a list section', byClass(root, 'main'), null);
expect('starts without a footer', byClass(root, 'footer'), null);

// A user types into the new-todo input and presses Enter. Re-query after the
// input event: the render it triggers may patch the node.
const newTodo = () => byRole(root, 'textbox', 'What needs to be done?');
const add = (title) => {
  newTodo().listeners.input({ target: { value: title } });
  newTodo().listeners.keydown({ key: 'Enter', preventDefault: () => {} });
};

work.mark();
add('  Buy milk  ');
expect('todo added', rows().length, 1);
expect('title trimmed', textOf(rows()[0]), 'Buy milk');
expect('count is singular', count(), '<strong>1</strong> item left');
expect('input cleared for the next todo', newTodo().value ?? '', '');
// The first todo brings the list section (its toggle-all, label, list and
// one row of six elements) and the footer (count, three filter links) into
// existence: 20 elements, placed as two subtrees.
work.expectDelta('first todo builds the list and footer', {
  elements: 20, inserts: 2, moves: 0, removals: 0, patchReplace: 0,
});

work.mark();
add('Walk the dog');
expect('both todos listed', rows().length, 2);
expect('count is plural', count(), '<strong>2</strong> items left');
// A second todo is one new row (li, div, toggle, label, destroy, edit) placed
// by one REORDER, plus the count's two text nodes. Nothing existing is
// rebuilt or moved.
work.expectDelta('second todo adds one row', {
  elements: 6, inserts: 1, moves: 0, removals: 0, patchReorder: 1, patchSetText: 2, patchReplace: 0,
});

// Toggle the first todo through its checkbox's change event.
const toggle = byClassAll(root, 'toggle')[0];
toggle.checked = true;
work.mark();
toggle.listeners.change({ target: toggle });
expect('toggled todo completed', byClassAll(root, 'completed').length, 1);
expect('count follows', count(), '<strong>1</strong> item left');
expect('toggle-all reachable by its label', byLabel(root, 'Mark all as complete').attrs.get('class'), 'toggle-all');
// Completing a todo makes the "Clear completed" button appear: one element,
// and the row is patched in place.
work.expectDelta('toggling adds the clear button', {
  elements: 1, inserts: 1, moves: 0, removals: 0, patchReplace: 0,
});
expect('clear button is the new element', byRole(root, 'button', 'Clear completed') !== null, true);

// Edit the second todo: dblclick its label, retype, commit with Enter.
find(root, 'Walk the dog').listeners.dblclick({});
expect('row enters editing', byClassAll(root, 'editing').length, 1);
const edit = byClassAll(rows()[1], 'edit')[0];
expect('edit starts from the title', edit.attrs.get('value'), 'Walk the dog');
work.mark();
edit.listeners.input({ target: { value: 'Walk the cat' } });
// Typing re-renders the same structure: no nodes, no text, and one attribute
// patch, the edit input's value. The other form controls on the page are
// untouched: their `value` and `checked` only get written when the view
// changes them (the runtime pins a control's property after its own event,
// see check_controlled_input.mjs).
work.expectDelta('typing an edit patches attributes only', {
  patchAttrs: 1, patchReplace: 0, patchReorder: 0, patchSetText: 0, elements: 0, textWrites: 0,
});
work.mark();
byClassAll(rows()[1], 'edit')[0].listeners.keydown({ key: 'Enter', preventDefault: () => {} });
expect('editing ends', byClassAll(root, 'editing').length, 0);
expect('edit committed', textOf(rows()[1]), 'Walk the cat');
work.expectDelta('committing writes the label text in place', {
  patchSetText: 1, textWrites: 1, patchReplace: 0, elements: 0, removals: 0,
});

// Clear completed drops the toggled todo and the button with it.
work.mark();
byRole(root, 'button', 'Clear completed').listeners.click();
expect('completed todo cleared', rows().length, 1);
expect('clear button gone', byRole(root, 'button', 'Clear completed'), null);
work.expectDelta('clearing removes the row and the button', {
  removals: 2, elements: 0, moves: 0, patchReplace: 0,
});

// Destroying the last todo brings the empty state back.
work.mark();
byClass(root, 'destroy').listeners.click();
expect('list section gone again', byClass(root, 'main'), null);
expect('footer gone again', byClass(root, 'footer'), null);
work.expectDelta('the empty state drops two subtrees', {
  removals: 2, elements: 0, patchReplace: 0,
});
