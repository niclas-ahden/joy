// Node harness for pointer: pointer events cross as typed PointerEvent
// records (coordinates, buttons bitmask, modifiers), prevent_default fires
// per handler, and hover without a held button is not a drag.
// Run from the repo root: node tests/check_pointer.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('pointer'));

function findById(node, id) {
  if (node instanceof El) {
    if (node.attrs?.get('id') === id) return node;
    for (const c of node.children) { const hit = findById(c, id); if (hit) return hit; }
  }
  return null;
}

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const pad = findById(root, 'pad');

expect('pad rendered', pad !== null, true);
expect('initially idle', htmlBare(root).includes('(idle)'), true);

// Press with shift held: coordinates land in the model, dragging starts,
// the shift modifier is seen.
let pdCalls = 0;
const ev = (props) => ({ preventDefault: () => { pdCalls += 1; }, ...props });
pad.listeners.pointerdown(ev({ offsetX: 12.5, offsetY: 20.5, clientX: 112.5, clientY: 220.5, pageX: 112.5, pageY: 620.5, button: 0, buttons: 1, shiftKey: true }));
expect('press coordinates delivered (offset_x/offset_y)', htmlBare(root).includes('At 12.5, 20.5'), true);
expect('dragging after press', htmlBare(root).includes('(dragging)'), true);
expect('shift modifier crossed', htmlBare(root).includes('Shift-clicks: 1'), true);
expect('plain pointerdown leaves the default alone', pdCalls, 0);

// Drag with the button held: coordinates update, the move counts, and the
// prevent_default flag on the move handler suppresses text selection.
pad.listeners.pointermove(ev({ offsetX: 30.5, offsetY: 40.5, buttons: 1 }));
expect('drag moved the point', htmlBare(root).includes('At 30.5, 40.5'), true);
expect('move counted', htmlBare(root).includes('Moves: 1'), true);
expect('prevent_default handler suppressed the default', pdCalls, 1);

// Hover (no button held): the handler fires but update ignores it.
pad.listeners.pointermove(ev({ offsetX: 99.5, offsetY: 99.5, buttons: 0 }));
expect('hover is not a drag', htmlBare(root).includes('At 30.5, 40.5'), true);
expect('hover not counted', htmlBare(root).includes('Moves: 1'), true);

// Release, then move with a button held: the drag ended, nothing counts.
pad.listeners.pointerup(ev({ buttons: 0 }));
expect('idle after release', htmlBare(root).includes('(idle)'), true);
pad.listeners.pointermove(ev({ offsetX: 1.5, offsetY: 1.5, buttons: 1 }));
expect('no drag after release', htmlBare(root).includes('At 30.5, 40.5'), true);

// A second press without shift: coordinates move, shift count stays.
pad.listeners.pointerdown(ev({ offsetX: 5.5, offsetY: 6.5, button: 0, buttons: 1 }));
expect('second press moved the point', htmlBare(root).includes('At 5.5, 6.5'), true);
expect('shift count unchanged', htmlBare(root).includes('Shift-clicks: 1'), true);

