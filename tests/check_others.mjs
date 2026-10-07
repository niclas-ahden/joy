// Node harness for a page others write to as well: a browser extension puts
// a control next to a video, a password manager an icon next to an input, a
// map draws into a container the app leaves empty, a translator wraps text.
// The runtime finds its nodes from its own node list and never by position
// in the DOM, so none of that may break a patch, move the app's nodes
// around or remove what others put there. Every step also runs through
// fakeDom.checkNodes, which holds the runtime's node list against the tree
// after each paint, and is held against a twin app nobody touches: the page
// without what others added must be the twin's page. Drives
// tests/apps/others.roc, whose messages cover every patch that changes the
// tree's shape.
// Run from the repo root: JOY_OPT=speed node tests/check_others.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, Text, byClass, byClassAll, fakeDom, html, others, parsedCopy, textOf } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const wasm = readFileSync(wasmPath('others'));

// An element of others', with a line of text in it.
const theirs = (tag, cls, text = '') => {
  const el = new El(tag);
  el.attrs.set('class', cls);
  if (text !== '') fakeDom.append(el, new Text(text));
  return el;
};

const inPage = (root, node) => {
  for (let p = node; p; p = p.parent) if (p === root) return true;
  return false;
};
const parentClass = (n) => n.parent?.attrs.get('class') ?? 'removed';

// The page as the app made it: what others added left out, what they
// wrapped shown where it is, attributes they set left out.
const ownHtml = (root, theirAttrs = []) => {
  const out = (n) => {
    if (n.byOthers) return (n.children ?? []).map(out).join('');
    if (n instanceof Text) return n.text;
    const attrs = [...n.attrs].filter(([k]) => !theirAttrs.includes(k)).map(([k, v]) => (v === '' ? ` ${k}` : ` ${k}="${v}"`)).join('');
    return `<${n.tag}${attrs}>${n.children.map(out).join('')}</${n.tag}>`;
  };
  return root.children.map(out).join('');
};

// One message clicked in the app and in its twin. A throw (a patch that
// failed, or checkNodes finding the node list off) is the step's outcome.
const click = (root, cls) => byClass(root, cls).listeners.click();
const step = (pair, cls) => {
  try {
    click(pair.root, cls);
    click(pair.twin, cls);
    return 'ok';
  } catch (err) {
    return err.message;
  }
};

const mountPair = async (root = new El('#root'), opts = {}) => {
  const app = await mount({ wasm, root, flags: '', dom: fakeDom, ...opts });
  const twin = new El('#root');
  await mount({ wasm, root: twin, flags: '', dom: fakeDom });
  return { root, twin, app };
};

// Every message, each one twice, in an order that keeps the list moving.
const SCRIPT = ['count', 'rotate', 'add', 'swap', 'rotate', 'spin', 'drop', 'open', 'spin', 'add', 'open', 'swap', 'fresh', 'rotate', 'open', 'drop', 'spin', 'fresh', 'open', 'count'];

// --- Between paints: others' nodes next to the app's, through every patch ---

{
  const pair = await mountPair();
  const { root } = pair;
  const page = byClass(root, 'others');
  const items = byClass(root, 'items');
  const theirNodes = [
    // A video speed control in front of the clip, which Swap replaces.
    [byClass(root, 'media'), theirs('vsc-controller', 'vsc', '1.00'), byClass(root, 'clip')],
    // A password manager's icon after the input.
    [page, theirs('span', 'pm-icon'), byClass(root, 'media')],
    // An ad between two items, which every message moves around.
    [items, theirs('div', 'ad', 'ad'), items.children[2]],
    // A map drawn into the container the app never fills.
    [byClass(root, 'map'), theirs('canvas', 'tiles'), null],
    // A badge in the panel while the app has nothing in it.
    [byClass(root, 'panel'), theirs('i', 'badge'), null],
    // Something at the very top, before the app's own first node.
    [root, theirs('aside', 'banner', 'hello'), page],
  ];
  for (const [parent, node, anchor] of theirNodes) others.insertBefore(parent, node, anchor);
  const kept = theirNodes.map(([, node]) => node);

  for (const [k, cls] of SCRIPT.entries()) {
    const label = `between paints, step ${k + 1} (${cls})`;
    expect(`${label}: patched`, step(pair, cls), 'ok');
    expect(`${label}: the page is the twin's`, ownHtml(root), html(pair.twin));
    expect(`${label}: others' nodes stay`, kept.filter((n) => !inPage(root, n)).map((n) => n.attrs.get('class')).join(' '), '');
  }
  expect('others\' nodes kept their places',
    kept.filter((n) => ['vsc', 'banner', 'tiles', 'badge'].includes(n.attrs.get('class')))
      .map((n) => `${n.attrs.get('class')} ${n.parent === root ? 'root' : parentClass(n)}`).join(),
    ['vsc media', 'tiles map', 'badge panel', 'banner root'].join());
  expect('the video speed control still sits in front of the clip',
    byClass(root, 'media')?.children.map((n) => n.tag).join(' '), `vsc-controller ${byClass(pair.twin, 'clip').tag}`);
}

// --- An empty container others fill, which the app then fills and empties ---

{
  const pair = await mountPair();
  const panel = byClass(pair.root, 'panel');
  const badge = theirs('i', 'badge');
  others.append(panel, badge);
  expect('opening the panel', step(pair, 'open'), 'ok');
  expect('the app\'s children come after the badge', panel.children.map((n) => n.tag).join(' '), 'i x-note p');
  expect('closing the panel', step(pair, 'open'), 'ok');
  expect('closing leaves the badge alone', panel.children.map((n) => n.tag).join(' '), 'i');
}

// --- A whole list replaced around a node of others' ---

{
  const pair = await mountPair();
  const items = byClass(pair.root, 'items');
  const ad = theirs('div', 'ad');
  others.insertBefore(items, ad, items.children[1]);
  expect('replacing every item', step(pair, 'fresh'), 'ok');
  expect('the ad is still in the list', ad.parent, items);
  expect('the new items are the twin\'s', ownHtml(pair.root), html(pair.twin));
}

// --- Others take one of the app's nodes away ---

{
  const pair = await mountPair();
  const items = byClass(pair.root, 'items');
  const [a, b] = items.children;
  // Rotate moves the last item in front of `a`, which is gone: the insert
  // must anchor on the next item still in the list.
  others.remove(a);
  expect('rotating past a removed item', step(pair, 'rotate'), 'ok');
  expect('the moved item went in front of the next one still there', items.children.map((n) => n.children[0]?.text).join(''), 'dbc');
  expect('the removed item stays removed', a.parent, null);
  expect('dropping the next item', step(pair, 'drop'), 'ok');
  expect('swapping inside the items', step(pair, 'swap'), 'ok');
  expect('the items still there follow the app', items.children.map((n) => `${n.children[0]?.text}${n.children[1]?.tag}`).join(' '), 'bem cem');
  expect('the app still answers', step(pair, 'count'), 'ok');
  expect('the count went up', byClass(pair.root, 'total')?.children[0]?.text, 'count 1');
  expect('b is still the app\'s', b.parent, items);
}

// --- Others take away a node the app then replaces ---

{
  const pair = await mountPair();
  const clip = byClass(pair.root, 'clip');
  others.remove(clip);
  expect('replacing a removed node', step(pair, 'swap'), 'ok');
  expect('its replacement stays off the page too', byClass(pair.root, 'media')?.children.length, 0);
  expect('replacing it back', step(pair, 'swap'), 'ok');
  expect('the app still answers after', step(pair, 'count'), 'ok');
}

// --- A translator wraps the app's text ---

{
  const pair = await mountPair();
  const total = byClass(pair.root, 'total');
  const firstItem = byClass(pair.root, 'items').children[0];
  const label = firstItem.children[0];
  others.wrap(total.children[0], theirs('font', 'translated'));
  others.wrap(label, theirs('font', 'translated'));
  for (const cls of ['count', 'rotate', 'spin', 'add', 'drop', 'count']) {
    expect(`wrapped text, ${cls}`, step(pair, cls), 'ok');
  }
  expect('the wrapped count text is still the one patched', total.children[0]?.children?.[0]?.text, 'count 2');
  expect('the page reads like the twin\'s', ownHtml(pair.root), html(pair.twin));
}

// --- Others insert while the runtime inserts ---
//
// A custom element's connectedCallback runs inside the insertion that
// connects it, so others can change the tree in the middle of a paint. Here
// every video that lands on the page gets a speed control in front of it
// right then, and every new item an ad in front of it.

{
  const root = new El('#root');
  const connected = (node) => {
    if (!inPage(root, node)) return;
    const walk = (n) => {
      if (n.byOthers || !(n instanceof El)) return;
      if (n.tag === 'video') others.insertBefore(n.parent, theirs('vsc-controller', 'vsc'), n);
      else if (n.attrs.get('class') === 'item' && n.parent.attrs.get('class') === 'items') others.insertBefore(n.parent, theirs('div', 'ad'), n);
      else for (const c of [...n.children]) walk(c);
    };
    walk(node);
  };
  const dom = {
    ...fakeDom,
    append: (parent, child) => { fakeDom.append(parent, child); connected(child); },
    insertBefore: (parent, node, anchor) => { fakeDom.insertBefore(parent, node, anchor); connected(node); },
    replaceNode: (old, fresh) => { fakeDom.replaceNode(old, fresh); connected(fresh); },
  };
  const pair = await mountPair(root, { dom });
  for (const [k, cls] of SCRIPT.entries()) {
    expect(`inserting mid-paint, step ${k + 1} (${cls})`, step(pair, cls), 'ok');
    expect(`inserting mid-paint, step ${k + 1}: the page is the twin's`, ownHtml(root), html(pair.twin));
  }
}

// --- Hydration: what others did while the app loaded ---

// The server's page for the app's first render, with the user's typing in
// the name field.
const serverPage = async (typed) => {
  const plain = new El('#root');
  await mount({ wasm, root: plain, flags: '', dom: fakeDom });
  const staged = parsedCopy(plain);
  byClass(staged, 'name').value = typed;
  return staged;
};

// The claim walk over `staged`, with `during` run while the wasm loads. A
// throw (checkNodes finding the claimed list off, say) is the outcome.
const hydrate = async (staged, during = () => {}) => {
  const warns = [];
  const realWarn = console.warn;
  console.warn = (...a) => warns.push(a.join(' '));
  try {
    const loading = mountPair(staged, { hydrate: true });
    // mount watches the root from its first line, before it awaits the wasm.
    during();
    return { ...(await loading), warns, outcome: 'ok' };
  } catch (err) {
    return { warns, outcome: err.message };
  } finally {
    console.warn = realWarn;
  }
};

{
  const staged = await serverPage('Ann');
  const clip = byClass(staged, 'clip');
  const input = byClass(staged, 'name');
  const total = byClass(staged, 'total');
  let vsc, icon, tiles;
  const pair = await hydrate(staged, () => {
    vsc = theirs('vsc-controller', 'vsc');
    others.insertBefore(clip.parent, vsc, clip);
    icon = theirs('span', 'pm-icon');
    others.insertBefore(input.parent, icon, input.parent.children[input.parent.children.indexOf(input) + 1]);
    tiles = theirs('canvas', 'tiles');
    others.append(byClass(staged, 'map'), tiles);
    others.setAttr(input, 'data-pm', 'filled');
    others.setText(total.children[0], 'antal 0');
  });
  expect('loading: hydrated', pair.outcome, 'ok');
  expect('loading: a clean claim', JSON.stringify(pair.app?.hydration()), '{"claimed":true,"mismatch":null}');
  expect('loading: no warning', pair.warns.length, 0);
  expect('loading: others\' nodes stay where they put them', [vsc, icon, tiles].map(parentClass).join(' '), 'media others map');
  expect('loading: the clip and the input were claimed', `${byClass(staged, 'clip') === clip} ${byClass(staged, 'name') === input}`, 'true true');
  expect('loading: their attribute stays', input.attrs.get('data-pm'), 'filled');
  expect('loading: the changed text is the app\'s again', total.children[0]?.text, 'count 0');
  expect('loading: the typing reached the app', byClass(staged, 'echo')?.children[0]?.text, 'name Ann');
  for (const [k, cls] of SCRIPT.entries()) {
    expect(`hydrated, step ${k + 1} (${cls})`, step(pair, cls), 'ok');
  }
  expect('hydrated: others\' nodes outlived it all', [vsc, icon, tiles].every((n) => inPage(staged, n)), true);
}

// --- Hydration: what others put in place of the page's while the app loaded ---
//
// A translator swaps the count's text for its translation and an extension
// wraps the clip in a box of its own, while a password manager puts its
// icon next to the field. The translation and the box stand in for the
// page's nodes: they go and the app's take their place back, so the page
// holds each once. The icon only sits next to the app's and stays. None of
// it is the server's doing, so none of it is reported.

{
  const staged = await serverPage('');
  const total = byClass(staged, 'total');
  const clip = byClass(staged, 'clip');
  const input = byClass(staged, 'name');
  let translation, box, icon;
  const pair = await hydrate(staged, () => {
    translation = theirs('font', 'translated', 'antal 0');
    others.replace(total.children[0], translation);
    box = theirs('div', 'box');
    others.wrap(clip, box);
    icon = theirs('span', 'pm-icon');
    others.insertBefore(input.parent, icon, input.parent.children[input.parent.children.indexOf(input) + 1]);
  });
  expect('stood in for: hydrated', pair.outcome, 'ok');
  expect('stood in for: a clean claim', JSON.stringify(pair.app?.hydration()), '{"claimed":true,"mismatch":null}');
  expect('stood in for: no warning', pair.warns.length, 0);
  expect('stood in for: the translation went', inPage(staged, translation), false);
  expect('stood in for: so did the box', inPage(staged, box), false);
  expect('stood in for: the count reads once, in the app\'s words', textOf(byClass(staged, 'total')), 'count 0');
  expect('stood in for: one clip', byClassAll(staged, 'clip').length, 1);
  expect('stood in for: the icon next to the field stays', parentClass(icon), 'others');
  expect('stood in for: the page is the twin\'s', ownHtml(staged), html(pair.twin));
  for (const [k, cls] of SCRIPT.entries()) {
    expect(`stood in for, then step ${k + 1} (${cls})`, step(pair, cls), 'ok');
  }
  expect('stood in for, then every message: the page is the twin\'s', ownHtml(staged), html(pair.twin));
  expect('stood in for, then every message: the icon outlived it all', inPage(staged, icon), true);
}

// One extension moves the first item's label into the map. The label is
// still the page's, so it is no node of theirs to keep in the map: the
// item gets the app's label back and the map holds only what the app puts
// in it.
// TODO: the label left in the map is reported as the server rendering more
// inside the <figure>. Telling a moved node from the server's would take
// the watcher's list of the nodes others took out.

{
  const staged = await serverPage('');
  const label = byClass(staged, 'item').children[0];
  const pair = await hydrate(staged, () => others.move(label, byClass(staged, 'map')));
  expect('moved: hydrated', pair.outcome, 'ok');
  expect('moved: the map holds only the app\'s', byClass(staged, 'map').children.length, 0);
  expect('moved: the page is the twin\'s', ownHtml(staged), html(pair.twin));
  for (const cls of ['rotate', 'add', 'swap', 'drop', 'count']) {
    expect(`moved, then ${cls}`, step(pair, cls), 'ok');
  }
  expect('moved, then every message: the page is the twin\'s', ownHtml(staged), html(pair.twin));
}

// --- Hydration: what others did before the app's script ran ---
//
// Nothing tells those nodes from the server's markup. One in front of a
// node the app expects is removed on its own, a mismatch, and the node after
// it is still claimed, with what the user typed in it.

{
  const staged = await serverPage('Ann');
  const clip = byClass(staged, 'clip');
  const input = byClass(staged, 'name');
  others.insertBefore(clip.parent, theirs('vsc-controller', 'vsc'), clip);
  others.insertBefore(input.parent, theirs('span', 'pm-icon'), input);
  const pair = await hydrate(staged);
  expect('before the script: hydrated', pair.outcome, 'ok');
  expect('before the script: reported', pair.app?.hydration().mismatch, 'expected <input> but found <span> in front of it');
  expect('before the script: one warning', pair.warns.length, 1);
  expect('before the script: the input was still claimed', byClass(staged, 'name'), input);
  expect('before the script: so was the clip', byClass(staged, 'clip'), clip);
  expect('before the script: the typing reached the app', byClass(staged, 'echo')?.children[0]?.text, 'name Ann');
  expect('before the script: the page is the app\'s', html(staged).includes('vsc-controller') || html(staged).includes('pm-icon'), false);
}
