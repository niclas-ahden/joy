// Shared tiny fake DOM for the node harnesses. Nodes are objects so tests can
// assert identity across diffs (reused vs rebuilt).
export class El {
  constructor(tag) {
    this.tag = tag;
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
// produces these from `<!-- ... -->`; joy-html never renders them, but
// hand-written SSR shells can contain them.
export class Comment {
  constructor(s) { this.text = s; this.parent = null; }
}

export const fakeDom = {
  createElement: (tag) => {
    const el = new El(tag);
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
  replaceNode: (oldNode, newNode) => {
    const p = oldNode.parent, i = p.children.indexOf(oldNode);
    p.children[i] = newNode; newNode.parent = p; oldNode.parent = null;
  },
  insertBefore: (parent, node, anchor) => {
    // Like the DOM: inserting a node that already has a parent moves it.
    if (node.parent) {
      const from = node.parent.children.indexOf(node);
      node.parent.children.splice(from, 1);
    }
    const at = anchor ? parent.children.indexOf(anchor) : parent.children.length;
    parent.children.splice(at, 0, node);
    node.parent = parent;
  },
  removeChild: (parent, node) => {
    parent.children.splice(parent.children.indexOf(node), 1);
    node.parent = null;
  },
  // Mirrors browserDom: live form-control state is the property, the
  // attribute only sets the default (tests poke node.value/node.checked
  // directly to simulate user interaction).
  setAttr: (node, k, v) => {
    node.attrs.set(k, v);
    if (k === 'value') node.value = v;
    else if (k === 'checked') node.checked = true;
    else if (k === 'selected') node.selected = true;
  },
  removeAttr: (node, k) => {
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
  getAttr: (n, k) => (n.attrs.has(k) ? n.attrs.get(k) : null),
  getProp: (n, k) => n[k],
  setProp: (n, k, v) => { n[k] = v; },
  // Every attached radio sharing the node's name, like the browser's group.
  radioGroup: (n) => (n.attrs.has('name')
    ? elements.filter((el) => el.parent !== null && el.tag === 'input' &&
        el.attrs.get('type') === 'radio' && el.attrs.get('name') === n.attrs.get('name'))
    : []),
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
// returns the first match in pre-order, or null; the `*All` variants return
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
// for test locators: aria-label wins; a form control is named by its labels,
// falling back to its placeholder or title (a button-like input to its
// value); anything else by its text.
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
