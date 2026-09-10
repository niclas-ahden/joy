// Node harness for hydration: mount({hydrate: true}) over a fake DOM staged
// the way a browser parses the fixture's SSR output (adjacent text merged,
// empty text dropped, boolean attrs bare), then assert the walk claimed the
// nodes instead of rebuilding them, repaired what it had to, and left the
// page fully interactive with patches landing on the claimed nodes.
// Run from the repo root: JOY_OPT=speed node tests/check_hydrate.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { Comment, El, Text, fakeDom, html } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('hydrate'));

// --- Staging: the DOM the parser would hand hydration ---

const el = (tag, attrs, children) => {
  const n = new El(tag);
  for (const [k, v] of Object.entries(attrs)) fakeDom.setAttr(n, k, v);
  for (const c of children) fakeDom.append(n, c);
  return n;
};
const tx = (s) => new Text(s);

// The fixture's view as parsed markup: "count: " and the number arrive as
// ONE text node and the view's empty text node as none, which is exactly
// what hydration has to untangle.
function ssrDom({ count, draft, items, on }) {
  const chk = { class: 'chk', type: 'checkbox' };
  if (on) chk.checked = '';
  return el('div', {}, [
    el('button', { class: 'inc' }, [tx('+')]),
    el('span', { class: 'greet' }, [tx(`count: ${count}`)]),
    el('input', { class: 'draft', value: draft }, []),
    el('input', chk, []),
    el('button', { class: 'add' }, [tx('add')]),
    el('ul', {}, items.map((s) => el('li', {}, [tx(s)]))),
  ]);
}

// A mount that spies on node creation, attribute writes and console.warn,
// so each scenario can say how much building and complaining hydration did.
async function hydrateMount(root, model, { hydrate = true } = {}) {
  const counts = { createdEls: 0, createdTexts: 0, attrWrites: 0, warns: [] };
  const dom = {
    ...fakeDom,
    createElement: (t) => { counts.createdEls += 1; return fakeDom.createElement(t); },
    createText: (s) => { counts.createdTexts += 1; return fakeDom.createText(s); },
    setAttr: (n, k, v) => { counts.attrWrites += 1; fakeDom.setAttr(n, k, v); },
  };
  const realWarn = console.warn;
  console.warn = (...args) => { counts.warns.push(args.join(' ')); };
  try {
    const app = await mount({ wasm: bytes, root, flags: JSON.stringify(model), dom, hydrate });
    return { app, counts };
  } finally {
    console.warn = realWarn;
  }
}

const model = { count: 0, draft: 'hi', items: ['milk', 'eggs'], on: true };

// The ground truth: what a plain client-side mount renders from this model.
const freshRoot = new El('#root');
const fresh = await hydrateMount(freshRoot, model, { hydrate: false });
const freshHtml = html(freshRoot);

expect('hydration() is null when hydrate is off', fresh.app.hydration(), null);

// --- The happy path: markup and first render agree ---

const root = new El('#root');
fakeDom.append(root, ssrDom(model));
const div = root.children[0];
const [incBtn, span, draft, chk, addBtn, list] = div.children;
const [li1, li2] = list.children;

const { app, counts } = await hydrateMount(root, model);

expect('hydrated page equals the client render', html(root), freshHtml);
expect('hydration() reports a clean claim', JSON.stringify(app.hydration()), '{"claimed":true,"mismatch":null}');
expect('no elements were built', counts.createdEls, 0);
expect('one text node was built (the empty one SSR cannot express)', counts.createdTexts, 1);
expect('no attribute was rewritten', counts.attrWrites, 0);
expect('nothing was warned', counts.warns.length, 0);

expect('the container was claimed, not rebuilt', root.children[0] === div, true);
expect('the buttons were claimed', div.children[0] === incBtn && div.children[4] === addBtn, true);
expect('the inputs were claimed', div.children[2] === draft && div.children[3] === chk, true);
expect('the list rows were claimed', list.children[0] === li1 && list.children[1] === li2, true);

// The merged "count: 0" was split back into the view's three text nodes.
expect('merged text was split to match the view', span.children.length, 3);
expect('split text contents', span.children.map((t) => t.text).join('|'), 'count: |0|');

// --- The page is live, and patches land on the claimed nodes ---

const countText = span.children[1];
incBtn.listeners.click();
expect('on_click reached the app', span.children.map((t) => t.text).join(''), 'count: 1');
expect('SET_TEXT hit the split node in place', span.children[1] === countText, true);

draft.listeners.input({ target: { value: 'bread' } });
addBtn.listeners.click();
expect('the claimed list grew a row', list.children.length, 3);
expect('existing rows were reused by the diff', list.children[0] === li1 && list.children[1] === li2, true);
expect('the new row rendered', list.children[2].children[0].text, 'bread');
expect('the draft was cleared', draft.attrs.get('value'), '');

chk.checked = false;
chk.listeners.change({ target: chk });
expect('on_check reached the app', chk.attrs.has('checked'), false);

// --- Pre-boot typing survives: matching values skip the write ---

{
  const r = new El('#root');
  fakeDom.append(r, ssrDom(model));
  const input = r.children[0].children[2];
  input.value = 'hi there'; // the user typed before the wasm arrived
  const m = await hydrateMount(r, model);
  expect('typed-ahead value survived hydration', input.value, 'hi there');
  expect('typing ahead is not a mismatch', m.counts.warns.length, 0);
}

// --- Comments are dropped on sight, silently ---

{
  const r = new El('#root');
  const d = ssrDom(model);
  d.children.splice(1, 0, new Comment(' server says hi '));
  fakeDom.append(d.children[3], new Comment('inside the span? sure'));
  fakeDom.append(r, d);
  const m = await hydrateMount(r, model);
  expect('comments removed, page equals the client render', html(r), freshHtml);
  expect('comments are not a mismatch', m.counts.warns.length, 0);
}

// --- Mismatches are repaired locally and warned about once ---

{
  const r = new El('#root');
  const d = ssrDom({ ...model, count: 5 }); // stale server data
  fakeDom.append(d, el('p', {}, [tx('oops, an extra node')]));
  fakeDom.append(r, d);
  const m = await hydrateMount(r, model);
  expect('stale text and extra node repaired', html(r), freshHtml);
  expect('one warning for the whole walk', m.counts.warns.length, 1);
  expect('the warning names hydration', m.counts.warns[0].includes('Joy hydrate'), true);
  expect('hydration() carries the mismatch', m.app.hydration().mismatch !== null, true);
  expect('hydration() still reports a claim', m.app.hydration().claimed, true);
}

// --- Truncated markup: the missing tail is built fresh ---

{
  const r = new El('#root');
  fakeDom.append(r, el('div', {}, [el('button', { class: 'inc' }, [tx('+')])]));
  const m = await hydrateMount(r, model);
  expect('missing tail built, page equals the client render', html(r), freshHtml);
  expect('truncation warned once', m.counts.warns.length, 1);
}

// --- An empty root hydrates as a plain build, no complaints ---

{
  const r = new El('#root');
  const m = await hydrateMount(r, model);
  expect('empty root renders the full page', html(r), freshHtml);
  expect('empty root is not a mismatch', m.counts.warns.length, 0);
  expect('hydration() reports the plain build', JSON.stringify(m.app.hydration()), '{"claimed":false,"mismatch":null}');
}

// --- hydrate demands the probes a custom adapter may lack ---

{
  const bad = { ...fakeDom };
  delete bad.elementTag;
  let threw = '';
  try {
    await mount({ wasm: bytes, root: new El('#root'), flags: JSON.stringify(model), dom: bad, hydrate: true });
  } catch (e) {
    threw = `${e.constructor.name}: ${e.message.includes('elementTag')}`;
  }
  expect('a probe-less adapter fails loudly', threw, 'TypeError: true');
}
