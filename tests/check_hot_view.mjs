// Node harness for what a hot reload (www/hot.js) does with the page's view.
// The rebuilt app makes the view its own by reusing every element that stays,
// so what the page keeps in an element survives (in a browser the focus, a
// typed value, an open <details>, a modal dialog), and it takes over the
// element's handlers and visibility observer. tests/apps/hot_view_v1.roc and
// hot_view_v2.roc are two builds of one view, and v1 says what v2 changes.
// tests.roc builds them with JOY_HOT.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_view.mjs
import { readFileSync } from 'node:fs';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
// Joy's dev module, which hot reloads every app mounted after it and gives it
// app.reload, exactly as in a page the dev server serves.
import '../www/hot.js';
import { El, activeObservers, fakeDom, html, modalCalls } from './fakedom.mjs';
import { expect, hotWasmPath, plainWasmPath } from './harness.mjs';

const view = (n) => readFileSync(hotWasmPath(`hot_view_v${n}`));

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};

async function start(n, dom = fakeDom, build = view) {
  const root = new El('#root');
  const app = await mount({ wasm: build(n), root, flags: '', dom });
  const el = (id) => byId(root, id);
  return {
    app,
    root,
    el,
    read: (id) => el(id).textContent,
    click: (id) => el(id).listeners.click(),
    // What a browser does when the user types: the field's value changes,
    // then it fires input.
    type: (value) => {
      el('name').value = value;
      el('name').listeners.input({ target: { value } });
    },
    tags: () => root.children[0].children.map((c) => c.tag).join(','),
  };
}

const observing = (node) => activeObservers().filter((o) => o.node === node);
const STAYS = ['name', 'typed', 'bump', 'count', 'more', 'open', 'confirm', 'sentinel', 'later'];

// --- The elements that stay are the page's own ---
{
  const t = await start(1);
  const before = Object.fromEntries([...STAYS, 'kind', 'footer'].map((id) => [id, t.el(id)]));
  const observed = observing(before.sentinel)[0];
  t.type('joy');
  t.click('bump');
  t.click('bump');
  // The user opens the <details>, which a browser marks with `open`.
  before.more.attrs.set('open', '');
  const r = await t.app.reload(view(2));
  expect('view: replayed it all', `${r.replayed}|${r.stopped}`, '3|null');
  expect('view: every element that stays is the same element', STAYS.filter((id) => t.el(id) !== before[id]).join(','), '');
  expect('view: the field keeps what was typed in it', t.el('name').value, 'joy');
  expect('view: an open <details> stays open', t.el('more').getAttribute('open'), '');
  expect('view: the state shows in it', `${t.read('typed')}|${t.read('count')}`, 'joy|2');
  expect('view: attributes are the new view\'s', `${t.el('bump').getAttribute('class')}|${t.el('bump').getAttribute('title')}`, 'loud|null');
  expect('view: an element whose tag changed is a new one', `${t.el('kind') === before.kind}|${t.el('kind').tag}|${t.read('kind')}`, 'false|strong|strong');
  expect('view: a dropped element is gone', `${t.el('footer')}|${before.footer.parent}`, 'null|null');
  expect('view: a new element goes where the new view has it, without moving the rest',
    t.tags(), 'h1,h2,input,p,button,p,strong,details,button,dialog,div,div,div');

  // The new app's handlers, and only those, are on the elements it kept.
  expect('view: a kept element has only the new app\'s listener',
    `${t.el('bump').listenerCount('click')}|${t.el('name').listenerCount('input')}`, '1|1');
  t.click('bump');
  expect('view: a kept element\'s handler runs the new app', t.read('count'), '3');
  t.type('joy!');
  expect('view: so does a kept field\'s', t.read('typed'), 'joy!');

  // So are its visibility observers.
  expect('view: the old app\'s observers are gone', observed.active, false);
  expect('view: one observer each', `${observing(t.el('sentinel')).length}|${observing(t.el('later')).length}`, '1|1');
  expect('view: an observer that stays the same does not report again what the old app was told',
    observing(t.el('sentinel'))[0].seen, true);
  expect('view: one whose re-arm key changed does', observing(t.el('later'))[0].seen, false);
  observing(t.el('sentinel'))[0].fire();
  expect('view: a kept observer reports to the new app', t.read('sentinel'), '1');
  t.app.unmount();
}

// --- The view ends exactly as the new build renders it ---
{
  const a = await start(1);
  a.type('joy');
  a.click('bump');
  await a.app.reload(view(2));
  const b = await start(2);
  b.type('joy');
  b.click('bump');
  expect('view: the same as the new build renders from scratch', html(a.root), html(b.root));
  // And it is a view the new app can patch: one more change through each.
  a.click('bump');
  b.click('bump');
  a.type('joy?');
  b.type('joy?');
  expect('view: and patches the same afterwards', html(a.root), html(b.root));
  a.app.unmount();
  b.app.unmount();
}

// --- Reloading into the same build changes nothing on the page ---
{
  const t = await start(1);
  t.type('fig');
  t.click('bump');
  const page = html(t.root);
  const nodes = [];
  const walk = (n) => { nodes.push(n); for (const c of n.children ?? []) walk(c); };
  walk(t.root);
  await t.app.reload(view(1));
  const after = [];
  const walkAfter = (n) => { after.push(n); for (const c of n.children ?? []) walkAfter(c); };
  walkAfter(t.root);
  expect('same build: the page reads the same', html(t.root), page);
  expect('same build: every node is the same node', after.length === nodes.length && after.every((n, i) => n === nodes[i]), true);
  t.app.unmount();
}

// --- A modal dialog stays open, unless the replay stops before it opened ---
{
  const t = await start(1);
  t.click('open');
  const dialog = t.el('confirm');
  expect('dialog: open', dialog.open, true);
  const shows = modalCalls.length;
  await t.app.reload(view(1));
  expect('dialog: a reload keeps it open, the same element', `${t.el('confirm') === dialog}|${dialog.open}`, 'true|true');
  // v2's Open button sends another message, so the replay stops before
  // Open, where the dialog was closed.
  const r = await t.app.reload(view(2));
  expect('dialog: the replay stopped before it opened', `${r.stopped?.text}|${r.stopped?.reason}`, 'Open|gone');
  expect('dialog: so it closes', `${t.el('confirm') === dialog}|${dialog.open}`, 'true|false');
  expect('dialog: with one close, and no show', modalCalls.slice(shows).filter((c) => c.kind === 'close').length, 1);
  t.click('open');
  expect('dialog: the new app opens it', dialog.open, true);
  t.click('close');
  expect('dialog: and closes it', dialog.open, false);
  t.app.unmount();
}

// --- An event the reload itself fires is an echo, and dropped ---
// In a browser, removing the focused element fires a blur at once. Here each
// node the reload removes fires a click on Bump, which the new app has taken
// over by then, in the middle of making the view its own. A hot build would
// not take the message anyway, as until it goes live it only takes the one
// it replays, so these are builds without hot reload, which restart.
{
  let echo = null;
  let echoes = 0;
  const echoing = { ...fakeDom, remove: (node) => { echo?.(); fakeDom.remove(node); } };
  const plain = (n) => readFileSync(plainWasmPath(`hot_view_v${n}`));
  const t = await start(1, echoing, plain);
  echo = () => {
    echoes++;
    t.el('bump').listeners.click();
  };
  const r = await t.app.reload(plain(2));
  echo = null;
  expect('echo: the reload restarted, removing nodes that each fired one', `${r.restarted}|${echoes > 0}`, 'true|true');
  t.click('bump');
  expect('echo: the new app got none of them', t.read('count'), '1');
  t.app.unmount();
}
