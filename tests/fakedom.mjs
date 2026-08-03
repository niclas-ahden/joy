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

export const fakeDom = {
  createElement: (tag) => {
    const el = new El(tag);
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
    node.listeners[event] = (domEvent) => { for (const f of [...node.bound[event]]) f(domEvent); };
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
  },
  closeModal: (selector) => {
    modalCalls.push({ kind: 'close', selector });
    const el = findDialog(selector);
    if (el && el.open) el.open = false;
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
