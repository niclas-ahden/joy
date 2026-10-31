// Node harness holding hot builds to plain ones. Each app runs one session
// twice side by side, as a plain build and as a hot build recording it as in
// the dev loop, and the two pages must read the same after every step. Then
// the hot one reloads into its own build, replaying the whole session, and
// must read the same again, and go on the same. So a hot build renders what
// a plain one does, and a replay what the session did. tests.roc builds
// these apps both ways.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_differential.mjs
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { mock } from 'node:test';
// Joy's dev module, which hot reloads every app mounted after it and gives it
// app.reload, exactly as in a page the dev server serves.
import '../www/hot.js';
import { El, FakeFile, activeGlobalListeners, activeObservers, fakeDom, html, popstate } from './fakedom.mjs';
import { expect, hotWasmPath, plainWasmPath } from './harness.mjs';

// Timers and the clock are node:test's, so both pages see the same times.
mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });
const flush = () => new Promise((resolve) => setImmediate(resolve));

// Every request is answered, with a body naming its URL, and a digest is
// worked out without the thread pool, so a flush settles both.
globalThis.fetch = async (url) => ({
  status: 200,
  headers: new Headers(),
  arrayBuffer: async () => new TextEncoder().encode(`from ${url}`).buffer,
});
globalThis.crypto.subtle.digest = async (algorithm, data) => createHash('sha256').update(new Uint8Array(data)).digest();

const find = (node, test) => {
  if (test(node)) return node;
  for (const c of node.children ?? []) {
    const hit = find(c, test);
    if (hit) return hit;
  }
  return null;
};

// Each page gets a runtime of its own, as features keep their state in the
// module, like the debounces under their keys.
async function open(path, tag) {
  const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js?${tag}`);
  const root = new El('#root');
  const app = await mount({ wasm: readFileSync(path), root, flags: '', dom: fakeDom });
  return {
    app,
    root,
    id: (id) => find(root, (n) => n.attrs?.get('id') === id),
    cls: (cls) => find(root, (n) => (n.attrs?.get('class') ?? '').split(' ').includes(cls)),
    // The element whose own text is `text`, of those with no element inside.
    text: (text) => find(root, (n) => n.children?.length > 0 && n.children.every((c) => c.text !== undefined) && n.textContent === text),
  };
}

// A step does something on a page, the same on both. One that takes no page
// happens to both at once: time passing, a key on the document, Back.
async function compare(name, steps, after) {
  const plain = await open(plainWasmPath(name), `plain-${name}`);
  const hot = await open(hotWasmPath(name), `hot-${name}`);
  let differs = null;
  for (const [i, step] of steps.entries()) {
    if (step.length === 0) {
      step();
    } else {
      step(plain);
      step(hot);
    }
    await flush();
    if (differs === null && html(plain.root) !== html(hot.root)) differs = `step ${i}: ${html(hot.root)}`;
  }
  expect(`${name}: a hot build renders what a plain one does, step by step`, differs, null);
  const recorded = globalThis.__JOY_HOT__.session(hot.app).flatMap((entry) => entry.msgs).length;
  const r = await hot.app.reload(readFileSync(hotWasmPath(name)));
  await flush();
  expect(`${name}: the replay runs every message`, `${r.replayed}|${r.stopped}|${r.skipped.length}`, `${recorded}|null|0`);
  expect(`${name}: and renders the session again`, html(hot.root), html(plain.root));
  after(plain);
  after(hot);
  await flush();
  expect(`${name}: and goes on the same`, html(hot.root), html(plain.root));
  plain.app.unmount();
  hot.app.unmount();
}

const type = (el, value) => {
  el.value = value;
  el.listeners.input({ target: { value } });
};
const enter = (el) => el.listeners.keydown({ key: 'Enter', code: 'Enter', preventDefault: () => {} });
const click = (el) => el.listeners.click();
const visible = (page, id) => activeObservers().find((o) => o.node === page.id(id)).fire();

await compare('spa-todomvc', [
  (p) => type(p.cls('new-todo'), 'Milk'),
  (p) => enter(p.cls('new-todo')),
  (p) => type(p.cls('new-todo'), 'Eggs'),
  (p) => enter(p.cls('new-todo')),
  (p) => {
    const toggle = p.cls('toggle');
    toggle.checked = true;
    toggle.listeners.change({ target: toggle });
  },
  (p) => p.text('Eggs').listeners.dblclick({}),
  (p) => type(p.cls('edit'), 'Tea'),
  (p) => enter(p.cls('edit')),
  (p) => click(p.text('Active')),
  (p) => click(p.text('All')),
  (p) => click(p.cls('clear-completed')),
], (p) => click(p.cls('destroy')));

await compare('hot_v1', [
  (p) => click(p.id('inc')),
  (p) => click(p.id('inc')),
  (p) => click(p.id('dec')),
  (p) => type(p.id('draft'), 'apple'),
  (p) => click(p.id('add')),
  (p) => type(p.id('draft'), 'pear'),
  (p) => click(p.id('add')),
  (p) => click(p.id('items').children.find((b) => b.textContent === 'pear')),
  (p) => click(p.id('fetch')),
  (p) => click(p.id('later')),
  () => mock.timers.tick(5),
  (p) => p.app.sendPort('ping', 'hello'),
], (p) => click(p.id('inc')));

await compare('hot_fx_v1', [
  (p) => click(p.id('bump')),
  (p) => click(p.id('save')),
  (p) => click(p.id('load')),
  (p) => click(p.id('remind')),
  (p) => type(p.id('search'), 'joy'),
  () => mock.timers.tick(300),
  (p) => click(p.id('hash')),
  (p) => click(p.id('pick-b')),
  (p) => click(p.id('label')),
  (p) => click(p.id('greet-sv')),
], (p) => click(p.id('bump')));

await compare('hot_src_v1', [
  (p) => enter(p.id('field')),
  (p) => p.id('pad').listeners.pointerdown({ clientX: 7 }),
  (p) => {
    const upload = p.id('upload');
    upload.fakeFile = new FakeFile('notes.txt', 'hi');
    upload.listeners.change({ target: upload });
  },
  (p) => visible(p, 'sentinel'),
  () => mock.timers.tick(1000),
  () => { for (const l of activeGlobalListeners()) l.fn({ key: 'Escape', code: 'Escape', preventDefault: () => {} }); },
  (p) => p.app.sendPort('ping', 'hi'),
  () => popstate('/next'),
], (p) => p.app.sendPort('ping', 'again'));

await compare('hot_view_v1', [
  (p) => type(p.id('name'), 'joy'),
  (p) => click(p.id('bump')),
  (p) => click(p.id('open')),
  (p) => click(p.id('close')),
  (p) => visible(p, 'sentinel'),
], (p) => click(p.id('bump')));

mock.timers.reset();
