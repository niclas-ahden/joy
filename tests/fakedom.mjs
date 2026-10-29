// Shared tiny fake DOM for the node harnesses. Nodes are objects so tests can
// assert identity across diffs (reused vs rebuilt).
import { foreignAttr, foreignTagName } from '../www/runtime.js';

// Elements carry a namespace key ('html', 'svg' or 'math', see the runtime's
// Namespaces notes), and a foreign element's attributes are stored under
// the names the HTML parser gives them, with the namespace of a prefixed
// one (xlink:href) in `attrNs`. Both use the runtime's own tables, so a
// harness checks that the runtime asks for the right namespace and the
// browser suite checks the tables against a real parser.
export class El {
  constructor(tag, ns = 'html') {
    this.tag = tag;
    this.ns = ns;
    this.attrNs = new Map();
    this.children = [];
    // Like addEventListener, an event can have several listeners; firing
    // `listeners[event]()` calls them all, so a runtime that double-binds
    // dispatches twice here exactly as it would in a browser.
    this.bound = {}; // event -> fn[]
    this.listeners = {};
    this.attrs = new Map();
    this.parent = null;
  }
  listenerCount(event) { return (this.bound[event] ?? []).length; }
}
export class Text {
  constructor(s) { this.text = s; this.parent = null; }
}

// Neither element nor text, so hydration must drop it on sight. The parser
// produces these from `<!-- ... -->`. joy-html never renders them, but
// hand-written SSR shells can contain them.
export class Comment {
  constructor(s) { this.text = s; this.parent = null; }
}

const isForeign = (n) => n.ns !== undefined && n.ns !== 'html';

// The live state of a control, like the browser's properties: a value or
// checked a test (standing in for the user) or the runtime assigned, else
// the default the markup gives it.
const options = (n) => n.children.flatMap((c) => (c instanceof El ? (c.tag === 'option' ? [c] : options(c)) : []));
const defaultValue = (n) => (n.tag === 'textarea'
  ? n.children.filter((c) => c instanceof Text).map((c) => c.text).join('')
  : n.attrs.get('value') ?? '');
const liveValue = (n) => n.value ?? defaultValue(n);
const liveChecked = (n) => n.checked ?? n.attrs.has('checked');
const isToggle = (n) => n.tag === 'input' && ['checkbox', 'radio'].includes(n.attrs.get('type'));
// A select's default selection: the last option the markup marks selected,
// else the first enabled one (none for a multiple select).
const defaultSelection = (n) => {
  const opts = options(n);
  if (n.attrs.has('multiple')) return opts.map((o) => o.attrs.has('selected'));
  let def = -1;
  opts.forEach((o, k) => { if (o.attrs.has('selected')) def = k; });
  if (def < 0) def = opts.findIndex((o) => !o.attrs.has('disabled'));
  return opts.map((_, k) => k === def);
};
const liveSelection = (n) => {
  const def = defaultSelection(n);
  return options(n).map((o, k) => o.selected ?? def[k]);
};

export const fakeDom = {
  createElement: (tag, ns = 'html') => {
    const el = new El(ns === 'html' ? tag : foreignTagName(ns, tag), ns);
    elements.push(el);
    if (tag === 'dialog') dialogs.push(el);
    return el;
  },
  createText: (s) => new Text(s),
  fragment: () => new El('#frag'),
  append: (parent, child) => { child.parent = parent; parent.children.push(child); },
  clear: (node) => {
    for (const c of node.children) c.parent = null;
    node.children = [];
  },
  on: (node, event, fn) => {
    (node.bound[event] ??= []).push(fn);
    // Browsers hand listeners currentTarget and type, harnesses call
    // `listeners.click()` bare, so the dispatcher fills both in. Mutates
    // the caller's event rather than copying: bubbling harnesses pass one
    // event through several nodes and rely on its identity.
    node.listeners[event] = (domEvent) => {
      const ev = domEvent ?? {};
      ev.currentTarget = node;
      ev.type = event;
      for (const f of [...node.bound[event]]) f(ev);
    };
  },
  setText: (node, s) => { node.text = s; },
  childrenOf: (node) => node.children ?? [],
  childCount: (node) => node.children.length,
  // Like replaceWith: a node without a parent stays without one, and so
  // does the new node.
  replaceNode: (oldNode, newNode) => {
    const p = oldNode.parent;
    if (p === null) return;
    if (newNode.parent) fakeDom.remove(newNode);
    const i = p.children.indexOf(oldNode);
    p.children[i] = newNode; newNode.parent = p; oldNode.parent = null;
  },
  insertBefore: (parent, node, anchor) => {
    // Like the DOM, which throws NotFoundError for an anchor that is not
    // the parent's child, rather than inserting somewhere else.
    if (anchor && anchor.parent !== parent) {
      throw new Error('NotFoundError: insertBefore: the anchor is not a child of the parent');
    }
    // Like the DOM: inserting a node that already has a parent moves it.
    if (node.parent) {
      const from = node.parent.children.indexOf(node);
      node.parent.children.splice(from, 1);
    }
    const at = anchor ? parent.children.indexOf(anchor) : parent.children.length;
    parent.children.splice(at, 0, node);
    node.parent = parent;
  },
  remove: (node) => {
    if (node.parent === null) return;
    node.parent.children.splice(node.parent.children.indexOf(node), 1);
    node.parent = null;
  },
  // Mirrors browserDom: live form-control state is the property, the
  // attribute only sets the default (tests poke node.value/node.checked
  // directly to simulate user interaction).
  nsOf: (n) => n.ns ?? 'html',
  parentOf: (n) => n.parent,
  setAttr: (node, k, v) => {
    if (isForeign(node)) {
      const a = foreignAttr(node.ns, k);
      node.attrs.set(a.name, v);
      if (a.ns === null) node.attrNs.delete(a.name);
      else node.attrNs.set(a.name, a.ns);
      return;
    }
    node.attrs.set(k, v);
    if (k === 'value') node.value = v;
    else if (k === 'checked') node.checked = true;
    else if (k === 'selected') node.selected = true;
  },
  removeAttr: (node, k, exact = false) => {
    if (isForeign(node)) {
      const a = exact ? { name: k } : foreignAttr(node.ns, k);
      node.attrs.delete(a.name);
      node.attrNs.delete(a.name);
      return;
    }
    node.attrs.delete(k);
    if (k === 'value') node.value = '';
    else if (k === 'checked') node.checked = false;
    else if (k === 'selected') node.selected = false;
  },
  // Mirrors browserDom.eventProp: read the wired property, stringified;
  // missing, null and NaN read as "".
  eventProp: (e, prop) => {
    const v = e?.target?.[prop];
    return v == null || v !== v ? '' : String(v);
  },
  eventKeyInfo: (e) => ({
    key: e?.key ?? '',
    code: e?.code ?? '',
    ctrl: !!e?.ctrlKey,
    shift: !!e?.shiftKey,
    alt: !!e?.altKey,
    meta: !!e?.metaKey,
    repeat: !!e?.repeat,
    isComposing: !!e?.isComposing,
  }),
  eventPointerInfo: (e) => ({
    clientX: e?.clientX ?? 0,
    clientY: e?.clientY ?? 0,
    pageX: e?.pageX ?? 0,
    pageY: e?.pageY ?? 0,
    offsetX: e?.offsetX ?? 0,
    offsetY: e?.offsetY ?? 0,
    button: e?.button > 0 ? e.button : 0,
    buttons: e?.buttons ?? 0,
    ctrl: !!e?.ctrlKey,
    shift: !!e?.shiftKey,
    alt: !!e?.altKey,
    meta: !!e?.metaKey,
  }),
  // Tests put a FakeFile on the input (node.fakeFile = ...) before firing
  // its change listener, mirroring a browser's e.target.files[0].
  eventFile: (e) => e?.target?.fakeFile ?? null,
  // Selector support is what the harnesses need: "#id" or a bare tag name,
  // resolved against every <dialog> ever created. Calls are recorded for
  // assertions.
  showModal: (selector) => {
    modalCalls.push({ kind: 'show', selector });
    const el = findDialog(selector);
    if (el && !el.open) el.open = true;
    return el !== null;
  },
  closeModal: (selector) => {
    modalCalls.push({ kind: 'close', selector });
    const el = findDialog(selector);
    if (el && el.open) el.open = false;
    return el !== null;
  },
  // Same selector support ("#id", ".class" or a bare tag), resolved against
  // every attached element. The focused element is recorded like the
  // browser's document.activeElement, and every call like the modal ones.
  // Like browserDom, all three report whether the selector matched.
  focus: (selector) => {
    focusCalls.push(selector);
    const el = findElement(selector);
    if (el) focused.el = el;
    return el !== null;
  },
  // The element a feature module looks up, by the same selectors.
  element: (selector) => findElement(selector),
  onGlobal: (event, fn) => {
    const listener = { event, fn, active: true };
    globalListeners.push(listener);
    return () => { listener.active = false; };
  },
  navigate: (url) => { navigations.push({ kind: 'navigate', url }); },
  pushUrl: (url) => { navigations.push({ kind: 'push', url }); fakeLocation.url = url; },
  replaceUrl: (url) => { navigations.push({ kind: 'replace', url }); fakeLocation.url = url; },
  onUrlChange: (fn) => {
    const listener = { fn, active: true };
    urlListeners.push(listener);
    return () => { listener.active = false; };
  },
  currentUrl: () => fakeLocation.url,
  setTitle: (title) => { fakeDocument.title = title; },
  scrollTo: (x, y) => { scrolls.push({ x, y }); },
  // A fake click event's target is an El.
  clickedAttr: (e, name) => {
    for (let el = e.target; el instanceof El; el = el.parent) {
      if (el.attrs.has(name)) return el.attrs.get(name);
    }
    return null;
  },
  textOf: (selector) => {
    const el = findElement(selector);
    return el === null ? null : textContent(el);
  },
  observeVisibility: (node, rootMargin, fire) => {
    const observer = { node, rootMargin, fire, active: true };
    observers.push(observer);
    return () => { observer.active = false; };
  },
  // The hydration probes, mirroring browserDom: node kind, text content,
  // splitting a merged text node in place, and reading attributes back
  // (null for absent, like getAttribute).
  elementTag: (n) => (n instanceof El ? n.tag : null),
  textValue: (n) => (n instanceof Text ? n.text : null),
  splitText: (n, offset) => {
    const rest = new Text(n.text.slice(offset));
    n.text = n.text.slice(0, offset);
    const sibs = n.parent.children;
    sibs.splice(sibs.indexOf(n) + 1, 0, rest);
    rest.parent = n.parent;
    return rest;
  },
  getAttr: (n, k, exact = false) => {
    const name = isForeign(n) && !exact ? foreignAttr(n.ns, k).name : k;
    return n.attrs.has(name) ? n.attrs.get(name) : null;
  },
  attrNames: (n) => [...n.attrs.keys()],
  attrName: (n, k) => (isForeign(n) ? foreignAttr(n.ns, k).name : k),
  // The pre-boot interaction probes, mirroring browserDom on the fake
  // properties above.
  userChanged: (n) => {
    if (n.tag === 'select') {
      const def = defaultSelection(n);
      return liveSelection(n).some((sel, k) => sel !== def[k]);
    }
    if (isToggle(n)) return liveChecked(n) !== n.attrs.has('checked');
    if (n.attrs.get('type') === 'file') return false;
    return liveValue(n) !== defaultValue(n);
  },
  controlState: (n) => (n.tag === 'select' ? liveSelection(n) : { value: liveValue(n), checked: liveChecked(n) }),
  restoreControlState: (n, s) => {
    if (Array.isArray(s)) options(n).forEach((o, k) => { if (k < s.length) o.selected = s[k]; });
    else if (isToggle(n)) n.checked = s.checked;
    else n.value = s.value;
  },
  getProp: (n, k) => n[k],
  setProp: (n, k, v) => { n[k] = v; },
  // Every attached radio sharing the node's name, like the browser's group.
  radioGroup: (n) => (n.attrs.has('name')
    ? elements.filter((el) => el.parent !== null && el.tag === 'input' &&
        el.attrs.get('type') === 'radio' && el.attrs.get('name') === n.attrs.get('name'))
    : []),
  // Like browserDom's MutationObserver, over the changes `others` makes.
  watchOthers: (root) => {
    const seen = { nodes: new Set(), attrs: new Map(), texts: new Set(), cut: new Set() };
    const watcher = { root, seen };
    watchers.add(watcher);
    return { take: () => { watchers.delete(watcher); return seen; } };
  },
  // Every harness holds the runtime's node list against the tree after each
  // paint: the app's nodes still under the root, in list order, must be the
  // nodes under the root in document order, less what others added. A
  // node somebody else took off the page leaves the list's view of it, one
  // they wrapped stays in it where the wrapper put it.
  checkNodes: (root, nodes) => {
    const inTree = new Set();
    const want = [];
    const stack = [...root.children].reverse();
    while (stack.length > 0) {
      const n = stack.pop();
      inTree.add(n);
      if (!n.byOthers) want.push(n);
      if (n.children) for (let k = n.children.length - 1; k >= 0; k--) stack.push(n.children[k]);
    }
    const got = nodes.filter((n) => inTree.has(n));
    let k = 0;
    while (k < got.length && k < want.length && got[k] === want[k]) k++;
    if (k < got.length || k < want.length) {
      throw new Error(`checkNodes: the node list and the tree part at ${k}: ${describeNode(got[k])} in the list, ${describeNode(want[k])} in the tree (${got.length} listed, ${want.length} in the tree)`);
    }
  },
};

// fakeDom without the node-list check, for the benches, which would time it.
export const uncheckedDom = { ...fakeDom, checkNodes: undefined };

// A server-rendered copy of a client build's root, the way the parser hands
// it over: same namespaces and names, adjacent text merged, empty text gone.
export const parsedCopy = (from) => {
  const r = new El('#root');
  for (const c of from.children) fakeDom.append(r, parsedClone(c));
  return r;
};
function parsedClone(node) {
  if (node instanceof Text) return new Text(node.text);
  const el = new El(node.tag, node.ns);
  for (const [k, v] of node.attrs) el.attrs.set(k, v);
  for (const [k, v] of node.attrNs) el.attrNs.set(k, v);
  let pending = null;
  for (const c of node.children) {
    if (c instanceof Text) { pending = (pending ?? '') + c.text; continue; }
    if (pending) fakeDom.append(el, new Text(pending));
    pending = null;
    fakeDom.append(el, parsedClone(c));
  }
  if (pending) fakeDom.append(el, new Text(pending));
  return el;
}

const describeNode = (n) => (n === undefined ? 'nothing'
  : n instanceof Text ? `text ${JSON.stringify(n.text)}`
  : n instanceof El ? `<${n.tag}>` : 'a comment');

// The watchOthers recordings in progress.
const watchers = new Set();
const within = (root, node) => {
  for (let p = node; p; p = p.parent) if (p === root) return true;
  return false;
};
const record = (node, note) => {
  for (const w of watchers) if (within(w.root, node)) note(w.seen);
};
const markOthers = (node) => {
  node.byOthers = true;
  for (const c of node.children ?? []) markOthers(c);
};

// Somebody else's hand on the page, a browser extension's or an embedded
// widget's: changes the runtime did not make. Nodes inserted through here
// are marked `byOthers`, with everything under them, which checkNodes leaves
// out, and a watchOthers running over the spot records each change.
export const others = {
  insertBefore: (parent, node, anchor = null) => {
    markOthers(node);
    fakeDom.insertBefore(parent, node, anchor);
    record(node, (seen) => seen.nodes.add(node));
  },
  append: (parent, node) => others.insertBefore(parent, node, null),
  // Taking a node of the page out is recorded against its parent, as a
  // MutationObserver reports it. Their own nodes come and go unrecorded.
  remove: (node) => {
    record(node, (seen) => { if (!seen.nodes.has(node)) seen.cut.add(node.parent); });
    fakeDom.remove(node);
  },
  // Put `wrapper` where `node` is and `node` inside it, the way a
  // translation extension wraps text. `node` stays the page's: a
  // MutationObserver reports it as added to the wrapper, but taken out of
  // the page first.
  wrap: (node, wrapper) => {
    const parent = node.parent;
    others.insertBefore(parent, wrapper, node);
    others.remove(node);
    fakeDom.append(wrapper, node);
  },
  // Put `theirs` where `node` is and take `node` off the page, the way a
  // page translator swaps a text for its translation.
  replace: (node, theirs) => {
    others.insertBefore(node.parent, theirs, node);
    others.remove(node);
  },
  // Move a node of the page to `parent`, in front of `anchor`. It stays the
  // page's, like a wrapped one.
  move: (node, parent, anchor = null) => {
    others.remove(node);
    fakeDom.insertBefore(parent, node, anchor);
  },
  // The attribute only, as setAttribute leaves a control's live state be.
  setAttr: (node, k, v) => {
    node.attrs.set(k, v);
    record(node, (seen) => {
      if (!seen.attrs.has(node)) seen.attrs.set(node, new Set());
      seen.attrs.get(node).add(k);
    });
  },
  setText: (node, s) => {
    node.text = s;
    record(node, (seen) => seen.texts.add(node));
  },
};

// Fake location + popstate: tests set the url and call popstate() to
// simulate the user pressing Back/Forward.
export const fakeLocation = { url: '/' };
export const urlListeners = [];
export const activeUrlListeners = () => urlListeners.filter((l) => l.active);
export function popstate(url) {
  fakeLocation.url = url;
  for (const l of activeUrlListeners()) l.fn();
}

// The fake document.title and every scrollTo call, in order.
export const fakeDocument = { title: '' };
export const scrolls = [];

// Every <dialog> element ever created, plus the modal calls made against
// them, for assertions. Dialogs track `open` like the browser's property.
export const dialogs = [];
export const modalCalls = [];
function findDialog(selector) {
  if (selector.startsWith('#')) {
    return dialogs.find((d) => d.attrs.get('id') === selector.slice(1)) ?? null;
  }
  return dialogs.find((d) => d.tag === selector) ?? null;
}

// Every element ever created, the focus calls made, and the element focus
// landed on (`focused.el`, the fake activeElement). A detached element
// cannot be focused, like in the browser.
export const elements = [];
export const focusCalls = [];
export const focused = { el: null };
const textContent = (n) => (n instanceof El ? n.children.map(textContent).join('') : n instanceof Text ? n.text : '');
function findElement(selector) {
  const attached = elements.filter((el) => el.parent !== null);
  if (selector.startsWith('#')) {
    return attached.find((el) => el.attrs.get('id') === selector.slice(1)) ?? null;
  }
  if (selector.startsWith('.')) {
    const cls = selector.slice(1);
    return attached.find((el) => (el.attrs.get('class') ?? '').split(' ').includes(cls)) ?? null;
  }
  return attached.find((el) => el.tag === selector) ?? null;
}

// A stand-in for a browser File: named bytes with the slice()/arrayBuffer()
// surface the runtime uses. Tests attach one to a file input (see
// fakeDom.eventFile) to simulate the user picking a file.
export class FakeFile {
  constructor(name, bytes, type = '') {
    this.name = name;
    this.bytes = bytes instanceof Uint8Array ? bytes : new TextEncoder().encode(bytes);
    this.type = type;
  }
  get size() { return this.bytes.length; }
  slice(start = 0, end = this.size) {
    return new FakeFile(this.name, this.bytes.slice(start, end), this.type);
  }
  async arrayBuffer() {
    // A fresh copy, like the browser (the caller may transfer or mutate it).
    return this.bytes.slice().buffer;
  }
}

// Recorded navigation calls, visibility observers and global (document)
// listeners, for assertions.
export const navigations = [];
export const observers = [];
export const activeObservers = () => observers.filter((o) => o.active);
export const globalListeners = [];
export const activeGlobalListeners = () => globalListeners.filter((l) => l.active);

const attrsToString = (n) =>
  n.attrs.size === 0 ? '' : ' ' + [...n.attrs].map(([k, v]) => (v === '' ? k : `${k}="${v}"`)).join(' ');

export const render = (n) =>
  n instanceof Text ? n.text : `<${n.tag}${attrsToString(n)}>${n.children.map(render).join('')}</${n.tag}>`;
export const html = (root) => root.children.map(render).join('');

// Render without attributes, for assertions that only care about structure.
export const renderBare = (n) =>
  n instanceof Text ? n.text : `<${n.tag}>${n.children.map(renderBare).join('')}</${n.tag}>`;
export const htmlBare = (root) => root.children.map(renderBare).join('');

// First element whose full text content equals `label`.
export function find(node, label) {
  if (node instanceof El) {
    if (node.tag !== '#root' && node.children.every((c) => c instanceof Text) &&
        node.children.map((c) => c.text).join('') === label) return node;
    for (const c of node.children) { const hit = find(c, label); if (hit) return hit; }
  }
  return null;
}

// First element with the given tag name (pre-order).
export function findTag(node, tag) {
  if (node instanceof El) {
    if (node.tag === tag) return node;
    for (const c of node.children) { const hit = findTag(c, tag); if (hit) return hit; }
  }
  return null;
}

// Semantic locators, the vocabulary of the browser suite (roc-playwright's
// role, label and test-id locators) on the fake tree, so a harness can say
// what a user sees instead of walking `children[1].children[0]`. Each
// returns the first match in pre-order, or null. The `*All` variants return
// every match.

// Every element (never text) matching pred, pre-order.
export function queryAll(node, pred, out = []) {
  if (node instanceof El) {
    if (node.tag !== '#root' && pred(node)) out.push(node);
    for (const c of node.children) queryAll(c, pred, out);
  }
  return out;
}
export const query = (node, pred) => queryAll(node, pred)[0] ?? null;

export const byId = (node, id) => query(node, (el) => el.attrs.get('id') === id);
export const byTestId = (node, id) => query(node, (el) => el.attrs.get('data-testid') === id);
export const byClassAll = (node, cls) =>
  queryAll(node, (el) => (el.attrs.get('class') ?? '').split(' ').includes(cls));
export const byClass = (node, cls) => byClassAll(node, cls)[0] ?? null;

// The text a user reads inside a node, whitespace collapsed like a browser
// lays it out.
export const textOf = (node) =>
  (node instanceof Text ? node.text : node.children.map(textOf).join('')).replace(/\s+/g, ' ').trim();

const FORM_CONTROLS = new Set(['input', 'textarea', 'select', 'button', 'meter', 'output', 'progress']);
const INPUT_ROLES = {
  checkbox: 'checkbox', radio: 'radio', button: 'button', submit: 'button', reset: 'button',
  image: 'button', range: 'slider', number: 'spinbutton', search: 'searchbox', hidden: null,
};
const TAG_ROLES = {
  button: 'button', textarea: 'textbox', option: 'option', h1: 'heading', h2: 'heading',
  h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading', ul: 'list', ol: 'list',
  li: 'listitem', nav: 'navigation', main: 'main', header: 'banner', footer: 'contentinfo',
  section: 'region', article: 'article', aside: 'complementary', form: 'form', dialog: 'dialog',
  img: 'img', table: 'table', tr: 'row', td: 'cell', th: 'columnheader', p: 'paragraph',
  progress: 'progressbar', hr: 'separator', menu: 'list',
};

// The element's ARIA role: an explicit `role` attribute, else the tag's
// implicit one (an <a> is only a link with an href, an <input> takes its
// role from `type`).
export function roleOf(el) {
  const explicit = el.attrs.get('role');
  if (explicit) return explicit;
  if (el.tag === 'a') return el.attrs.has('href') ? 'link' : null;
  if (el.tag === 'input') {
    const type = el.attrs.get('type') ?? 'text';
    return type in INPUT_ROLES ? INPUT_ROLES[type] : 'textbox';
  }
  if (el.tag === 'select') return el.attrs.has('multiple') ? 'listbox' : 'combobox';
  return TAG_ROLES[el.tag] ?? null;
}

const contains = (ancestor, node) => {
  for (let n = node.parent; n; n = n.parent) if (n === ancestor) return true;
  return false;
};

// The <label>s naming a control: `for` pointing at its id, or wrapping it.
const labelsFor = (root, el) => {
  const id = el.attrs.get('id');
  return queryAll(root, (l) => l.tag === 'label' && ((id != null && l.attrs.get('for') === id) || contains(l, el)));
};

// The element's accessible name, close enough to the browser's computation
// for test locators: aria-label wins, then a form control is named by its
// labels, falling back to its placeholder or title (a button-like input to
// its value), and anything else by its text.
export function nameOf(root, el) {
  const aria = el.attrs.get('aria-label');
  if (aria != null) return aria.replace(/\s+/g, ' ').trim();
  if (FORM_CONTROLS.has(el.tag)) {
    const labels = labelsFor(root, el);
    if (labels.length > 0) return labels.map(textOf).join(' ').trim();
    if (el.tag === 'input' && ['button', 'submit', 'reset'].includes(el.attrs.get('type'))) {
      return (el.attrs.get('value') ?? '').trim();
    }
    if (el.tag !== 'button') return (el.attrs.get('placeholder') ?? el.attrs.get('title') ?? '').trim();
  }
  return textOf(el);
}

// Elements with the role, optionally narrowed to an exact accessible name:
// byRole(root, 'button', 'Clear completed'), byRole(root, 'listitem').
export const byRoleAll = (root, role, name) =>
  queryAll(root, (el) => roleOf(el) === role && (name === undefined || nameOf(root, el) === name));
export const byRole = (root, role, name) => byRoleAll(root, role, name)[0] ?? null;

// The control a <label> with exactly this text names: the element its `for`
// points at, else the first control inside it.
export function byLabel(root, text) {
  for (const label of queryAll(root, (el) => el.tag === 'label' && textOf(el) === text)) {
    const id = label.attrs.get('for');
    const control = id != null
      ? byId(root, id)
      : query(label, (el) => FORM_CONTROLS.has(el.tag));
    if (control) return control;
  }
  return null;
}
