// Node harness for what a hot reload leaves alone: the nodes and attributes
// other scripts put into the app's view, as a widget drawn into one of its
// elements or an extension's marker on a button. A paint never touches them,
// and a rebuilt app that makes the page's view its own must not either (see
// `morph` and `keep` in www/hot.js). What the old view itself put there and
// the new one lacks still goes.
// tests/apps/hot_view_v1.roc and hot_view_v2.roc, built by tests.roc with
// JOY_HOT. Run from the repo root: JOY_OPT=speed node tests/check_hot_others.mjs
import { readFileSync } from 'node:fs';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, byId, fakeDom, others } from './fakedom.mjs';
import { expect, hotWasmPath } from './harness.mjs';

const view = (n) => readFileSync(hotWasmPath(`hot_view_v${n}`));
const root = new El('#root');
const app = await mount({ wasm: view(1), root, flags: '', dom: fakeDom });
const el = (id) => byId(root, id);
const frame = root.children[0];

// Another script's doing: a widget among the view's elements, one inside an
// element of the view, and an attribute on a button.
const widget = fakeDom.createElement('aside');
others.insertBefore(frame, widget, el('count'));
const inside = fakeDom.createElement('mark');
others.append(el('more'), inside);
others.setAttr(el('bump'), 'data-extension', 'on');
el('bump').listeners.click();

expect('v1: the view has its own title on the button', el('bump').attrs.get('title'), 'Add one');

await app.reload(view(2));
expect('v2: the count came along', el('count').children[0].text, '1');
expect('v2: the widget among the elements is still there', widget.parent === frame && frame.children.includes(widget), true);
expect('v2: and the one inside an element', inside.parent === el('more'), true);
expect('v2: the attribute another script set stays', el('bump').attrs.get('data-extension'), 'on');
expect('v2: the attribute the old view set and the new one lacks goes', el('bump').attrs.has('title'), false);
expect('v2: and one both set has the new value', el('bump').attrs.get('class'), 'loud');

// The rebuilt app knows the view's attributes on the elements it kept, so
// the next rebuild tells them apart as well.
await app.reload(view(1));
expect('v1 again: the title is back', el('bump').attrs.get('title'), 'Add one');
await app.reload(view(2));
expect('v2 again: and goes again', el('bump').attrs.has('title'), false);
expect('v2 again: the class an earlier build set is the view\'s to change', el('bump').attrs.get('class'), 'loud');
expect('v2 again: what another script did is still there', `${el('bump').attrs.get('data-extension')}|${frame.children.includes(widget)}|${inside.parent === el('more')}`, 'on|true|true');
el('bump').listeners.click();
expect('v2 again: and the app goes on', el('count').children[0].text, '2');
