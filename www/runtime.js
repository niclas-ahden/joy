// Joy runtime: drive the WASM loop and paint its command buffer into the DOM.
//
// The host renders internally (start()/dispatch()/dispatch_value() fill the
// command buffer). The first paint is a full build. Later paints are diffs:
// the host emits patch ops addressing nodes by their pre-order index, which
// the runtime tracks in a retained `nodeList`.
//
// Command buffer: word 0 is the mode; the rest are ops.
//   MODE_FULL (0): build ops build the whole tree
//   MODE_PATCH (1): patch ops mutate the existing DOM
// Build ops:
//   OPEN(1) tag | CLOSE(2) | TEXT(3) str
//   MSG_EVENT(4) name pd sp handler_id | ATTR(7) key val
//   BOOL_ATTR(8) key flag | VALUE_EVENT(9) name prop pd sp handler_id
//   KEY_EVENT(13) name pd sp handler_id n_keys (key)* | VISIBLE(11) margin key handler_id
//   POINTER_EVENT(14) name pd sp handler_id | FILE_EVENT(15) handler_id
// Patch ops:
//   SET_TEXT(5) idx str | REPLACE(6) idx n_words <build ops...>
//   PATCH_ATTRS(10) idx n_words <attr ops...>
//   REORDER(12) parent_idx n_children <descriptors...>, which rewrites a child
//     list. One descriptor per child of the new list, in order:
//       STAY(0) old_pos | MOVE(1) old_pos | NEW(2) n_words <build ops...>
//     Old children not referenced by any descriptor are removed. STAY nodes
//     are already in relative order (the host's LIS pass guarantees it), so
//     only MOVE/NEW nodes are (re)inserted.
// A handler_id is an opaque u32 the host mints per handler (a boxed Roc
// message, a boxed Str -> msg decoder for value events, or a boxed
// KeyEvent -> msg decoder for key events); the runtime never interprets it,
// only passes it back. Handler ids are refreshed by PATCH_ATTRS on every
// re-render, because the boxes are new each render.
const OP_ELEMENT_OPEN = 1;
const OP_ELEMENT_CLOSE = 2;
const OP_TEXT = 3;
const OP_MSG_EVENT = 4;
const OP_SET_TEXT = 5;
const OP_REPLACE = 6;
const OP_ATTR = 7;
const OP_BOOL_ATTR = 8;
const OP_VALUE_EVENT = 9;
const OP_PATCH_ATTRS = 10;
const OP_VISIBLE = 11;
const OP_REORDER = 12;
const OP_KEY_EVENT = 13;
const OP_POINTER_EVENT = 14;
const OP_FILE_EVENT = 15;
const OP_REFRESH_HANDLERS = 16;
const REORDER_STAY = 0;
const REORDER_MOVE = 1;
const REORDER_NEW = 2;
const MODE_FULL = 0;
const MODE_PATCH = 1;

// `dom` interface:
//   createElement(tag) -> node ; createText(s) -> node ; fragment() -> node
//   append(parent, child) ; clear(node) ; on(node, event, fn)
//   setText(textNode, s) ; childrenOf(node) -> node[] ; replaceNode(old, new)
//   insertBefore(parent, node, anchorOrNull) ; removeChild(parent, node)
//   setAttr(node, k, v) ; removeAttr(node, k) ; eventProp(domEvent, prop) -> string
//   eventKeyInfo(domEvent) -> {key, code, ctrl, shift, alt, meta, repeat}
//   eventPointerInfo(domEvent) -> {clientX..offsetY, button, buttons, ctrl..meta}
//   eventFile(domEvent) -> File | null ; showModal(sel) ; closeModal(sel)
export function makeRuntime(exports, dom, root) {
  const { memory } = exports;
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let nodeList = []; // DOM nodes in pre-order, matching the host's node indices

  const words = () => new Uint32Array(memory.buffer, exports.cmd_ptr(), exports.cmd_len());
  const str = (ptr, len) => decoder.decode(new Uint8Array(memory.buffer, ptr, len));

  // Ports the app subscribes to (via Port.listen): name -> the host's sub id.
  const ports = new Map();

  // JS handlers for outgoing ports (via app.onPort): name -> function.
  const outPorts = new Map();

  // Cleanup functions for active subscriptions (clear an interval, remove a
  // global key listener), keyed by the host's sub id. The host owns the
  // lifecycle: start/stop effects arrive whenever the app's declared
  // subscription set changes.
  const subCleanups = new Map();

  // User-picked File objects (from file inputs with an on_file handler),
  // keyed by the id minted when the pick was dispatched. The bytes stay on
  // the JS side; Http.post_file / Crypto.digest_file reference them by id.
  const files = new Map();
  let nextFileId = 1;

  // Pending Time.debounce timers by key: re-arming clears the old timer and
  // releases the callback it held (the fresh command carries a fresh one).
  const debounces = new Map(); // key -> { handle, cb }
  function dropDebounce(key) {
    const prev = debounces.get(key);
    if (!prev) return;
    clearTimeout(prev.handle);
    exports.drop_timer_cb(prev.cb);
    debounces.delete(key);
  }

  // Per-node attribute/handler bookkeeping, so a PATCH_ATTRS can remove what
  // is no longer set. Event listeners are bound once per (node, event) and
  // look their current handler up here, so re-renders never re-bind.
  // `bound` outlives `events`: removing a handler only deletes its descriptor
  // (the DOM listener stays attached but inert), so `bound` is what stops a
  // later re-add from attaching a second listener.
  const nodeState = new WeakMap(); // node -> { attrs:Set, bools:Set, events:Map(name -> {kind, id}), bound:Set, vis }
  const stateFor = (node) => {
    let s = nodeState.get(node);
    if (!s) {
      s = { attrs: new Set(), bools: new Set(), events: new Map(), bound: new Set(), vis: null };
      nodeState.set(node, s);
    }
    return s;
  };

  // Attach or re-arm a visibility observer. A fresh observer reports the
  // current intersection state, so recreating it when the rearm key changes
  // re-checks visibility (see Attribute.on_visible in the platform).
  function setVisibility(node, margin, key, id) {
    const s = stateFor(node);
    if (s.vis && s.vis.margin === margin && s.vis.key === key) {
      s.vis.id = id; // same observer, refreshed handler
      return;
    }
    s.vis?.disconnect();
    const disconnect = dom.observeVisibility(node, margin, () => {
      const v = stateFor(node).vis;
      if (v) dispatch(v.id);
    });
    s.vis = { margin, key, id, disconnect };
  }

  function setHandler(node, name, desc) {
    const s = stateFor(node);
    if (!s.bound.has(name)) {
      s.bound.add(name);
      dom.on(node, name, (domEvent) => {
        // Patching the DOM can itself fire events synchronously: hiding or
        // removing a focused element fires blur before the patch finishes.
        // Dispatching mid-paint would re-enter the host against a nodeList
        // that no longer matches the DOM (and a handler id the host already
        // dropped), corrupting the page. Such events are echoes of the state
        // change being painted, so they are dropped, not deferred.
        if (painting) return;
        const d = stateFor(node).events.get(name);
        if (!d) return; // handler was removed by a later patch
        // Stopping propagation is about this element swallowing the event, not
        // about which msg it produces, so it runs before any per-kind work and
        // independently of preventDefault. preventDefault stays per-kind
        // because a key handler's filter must run first: an unmatched key
        // passes through with its browser default intact. Every handler kind
        // carries both flags except file, where they read as undefined.
        if (d.stopPropagation) domEvent.stopPropagation?.();
        if (d.kind === 'msg') {
          if (d.preventDefault) domEvent.preventDefault?.(); // e.g. on_submit
          dispatch(d.id);
        } else if (d.kind === 'key') {
          const info = dom.eventKeyInfo(domEvent);
          if (d.keys.length > 0 && !d.keys.includes(info.key)) return;
          if (d.preventDefault) domEvent.preventDefault?.();
          dispatchKey(d.id, info);
        } else if (d.kind === 'pointer') {
          if (d.preventDefault) domEvent.preventDefault?.();
          dispatchPointer(d.id, dom.eventPointerInfo(domEvent));
        } else if (d.kind === 'file') {
          const file = dom.eventFile(domEvent);
          if (file) dispatchFile(d.id, file); // clearing the input is not a pick
        } else {
          if (d.preventDefault) domEvent.preventDefault?.();
          dispatchValue(d.id, dom.eventProp(domEvent, d.prop));
        }
      });
    }
    s.events.set(name, desc);
  }

  // Attributes the view is not allowed to set: `on*` attributes execute
  // their value as script, and `javascript:` URLs execute on click. Views
  // routinely interpolate user data into attribute values, so the runtime is
  // the layer that refuses these (real event handlers go through the typed
  // event ops, never through string attributes).
  const URL_ATTRS = new Set(['href', 'src', 'action', 'formaction', 'xlink:href']);
  function attrAllowed(k, v) {
    const key = k.toLowerCase();
    if (key.startsWith('on')) return false;
    if (URL_ATTRS.has(key)) {
      // Browsers strip control chars and whitespace when parsing the scheme.
      const scheme = v.replace(/[\u0000-\u0020]/g, '').toLowerCase();
      if (scheme.startsWith('javascript:')) return false;
    }
    return true;
  }

  // Apply the attr-op range [i, end) to `node`; returns the next index.
  // `fresh` collects what was set, so patches can drop stale attrs after.
  function applyAttrOps(w, i, end, node, fresh) {
    while (i < end) {
      const op = w[i++];
      if (op === OP_ATTR) {
        const k = str(w[i++], w[i++]);
        const v = str(w[i++], w[i++]);
        if (attrAllowed(k, v)) {
          dom.setAttr(node, k, v);
          stateFor(node).attrs.add(k);
          fresh?.attrs.add(k);
        }
      } else if (op === OP_BOOL_ATTR) {
        const k = str(w[i++], w[i++]);
        const on = w[i++] !== 0 && attrAllowed(k, '');
        if (on) {
          dom.setAttr(node, k, '');
          stateFor(node).bools.add(k);
          fresh?.bools.add(k);
        } else {
          dom.removeAttr(node, k);
          stateFor(node).bools.delete(k);
        }
      } else if (op === OP_MSG_EVENT) {
        const name = str(w[i++], w[i++]);
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'msg', preventDefault, stopPropagation, id: w[i++] });
        fresh?.events.add(name);
      } else if (op === OP_VALUE_EVENT) {
        const name = str(w[i++], w[i++]);
        const prop = str(w[i++], w[i++]);
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'value', prop, preventDefault, stopPropagation, id: w[i++] });
        fresh?.events.add(name);
      } else if (op === OP_KEY_EVENT) {
        const name = str(w[i++], w[i++]);
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        const id = w[i++];
        const keys = [];
        let nKeys = w[i++];
        while (nKeys-- > 0) keys.push(str(w[i++], w[i++]));
        setHandler(node, name, { kind: 'key', preventDefault, stopPropagation, keys, id });
        fresh?.events.add(name);
      } else if (op === OP_POINTER_EVENT) {
        const name = str(w[i++], w[i++]);
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'pointer', preventDefault, stopPropagation, id: w[i++] });
        fresh?.events.add(name);
      } else if (op === OP_FILE_EVENT) {
        setHandler(node, 'change', { kind: 'file', id: w[i++] });
        fresh?.events.add('change');
      } else if (op === OP_VISIBLE) {
        const margin = str(w[i++], w[i++]);
        const key = str(w[i++], w[i++]);
        setVisibility(node, margin, key, w[i++]);
        if (fresh) fresh.vis = true;
      } else {
        return i - 1; // not an attr op: caller resumes here
      }
    }
    return i;
  }

  // Replace `node`'s attribute set with the ops in [i, end).
  function patchAttrs(w, i, end, node) {
    const s = stateFor(node);
    const before = { attrs: new Set(s.attrs), bools: new Set(s.bools), events: new Set(s.events.keys()), hadVis: s.vis !== null };
    const fresh = { attrs: new Set(), bools: new Set(), events: new Set(), vis: false };
    applyAttrOps(w, i, end, node, fresh);
    for (const k of before.attrs) if (!fresh.attrs.has(k)) { dom.removeAttr(node, k); s.attrs.delete(k); }
    for (const k of before.bools) if (!fresh.bools.has(k)) { dom.removeAttr(node, k); s.bools.delete(k); }
    for (const name of before.events) if (!fresh.events.has(name)) s.events.delete(name);
    if (before.hadVis && !fresh.vis) { s.vis?.disconnect(); s.vis = null; }
  }

  // Build the balanced op range [start, end) into `parent`; return the next index.
  function buildRange(w, start, end, parent) {
    const stack = [parent];
    const top = () => stack[stack.length - 1];
    let i = start;
    while (i < end) {
      const op = w[i];
      if (op === OP_ELEMENT_OPEN) {
        i += 1;
        const el = dom.createElement(str(w[i++], w[i++]));
        dom.append(top(), el);
        stack.push(el);
      } else if (op === OP_ELEMENT_CLOSE) {
        i += 1;
        stack.pop();
      } else if (op === OP_TEXT) {
        i += 1;
        dom.append(top(), dom.createText(str(w[i++], w[i++])));
      } else if (op === OP_ATTR || op === OP_BOOL_ATTR || op === OP_MSG_EVENT || op === OP_VALUE_EVENT || op === OP_KEY_EVENT || op === OP_POINTER_EVENT || op === OP_FILE_EVENT || op === OP_VISIBLE) {
        i = applyAttrOps(w, i, end, top(), null);
      } else {
        throw new Error(`unknown build op ${op} at word ${i}`);
      }
    }
    return i;
  }

  // Disconnect visibility observers in a subtree that is about to be
  // discarded (full rebuild or REPLACE), so they cannot fire or leak.
  function cleanupSubtree(node) {
    const s = nodeState.get(node);
    if (s?.vis) { s.vis.disconnect(); s.vis = null; }
    for (const c of dom.childrenOf(node)) cleanupSubtree(c);
  }

  // Pre-order list of the DOM nodes under `root` (root itself excluded).
  function preorder() {
    const out = [];
    const visit = (n) => { out.push(n); for (const c of dom.childrenOf(n)) visit(c); };
    for (const c of dom.childrenOf(root)) visit(c);
    return out;
  }

  // Append a freshly built subtree's nodes in pre-order (for the REORDER
  // splice, where only NEW children need an actual walk).
  function collectPreorder(n, out) {
    out.push(n);
    for (const c of dom.childrenOf(n)) collectPreorder(c, out);
  }

  function paint() {
    const w = words();
    painting = true;
    try {
      paintApply(w);
    } finally {
      painting = false;
    }
  }

  function paintApply(w) {
    // Rebuilding the pre-order node list costs O(total nodes) per paint, so
    // skip it when every op left the tree's shape alone (SET_TEXT and
    // PATCH_ATTRS mutate nodes in place; REPLACE and REORDER change the
    // node set).
    let structural = false;
    // A paint whose only structural op is a single REORDER can splice the
    // node list from what it already knows (the host sends each kept child's
    // old pre-order start and subtree size), skipping the full DOM re-walk.
    // Anything else structural falls back to preorder().
    let structuralOps = 0;
    let splice = null;
    if (w[0] === MODE_FULL) {
      structural = true;
      cleanupSubtree(root);
      dom.clear(root);
      buildRange(w, 1, w.length, root);
    } else {
      const refs = nodeList;
      let i = 1;
      while (i < w.length) {
        const op = w[i++];
        if (op === OP_SET_TEXT) {
          const idx = w[i++];
          dom.setText(refs[idx], str(w[i++], w[i++]));
        } else if (op === OP_REPLACE) {
          structural = true;
          structuralOps += 1;
          const idx = w[i++];
          const n = w[i++];
          const holder = dom.fragment();
          buildRange(w, i, i + n, holder);
          i += n;
          cleanupSubtree(refs[idx]);
          dom.replaceNode(refs[idx], dom.childrenOf(holder)[0]);
        } else if (op === OP_PATCH_ATTRS) {
          const idx = w[i++];
          const n = w[i++];
          patchAttrs(w, i, i + n, refs[idx]);
          i += n;
        } else if (op === OP_REFRESH_HANDLERS) {
          // The element's attributes are unchanged except that its handlers
          // were re-boxed by the render (they always are), so only the stored
          // handler ids move, with no attribute writes and no listener
          // rebinding.
          const s = stateFor(refs[w[i++]]);
          const n = w[i++];
          for (let k = 0; k < n; k++) {
            const name = str(w[i++], w[i++]);
            const id = w[i++];
            const d = s.events.get(name);
            if (d) d.id = id;
          }
        } else if (op === OP_REORDER) {
          structural = true;
          structuralOps += 1;
          const parentIdx = w[i++];
          const oldSpan = w[i++];
          const parent = refs[parentIdx];
          const n = w[i++];
          const oldChildren = [...dom.childrenOf(parent)];
          // Resolve every descriptor to a node first (building NEW subtrees),
          // so old positions are read before the DOM mutates. segNodes
          // accumulates the segment's new pre-order for the splice.
          const placed = [];
          const used = new Set();
          const segNodes = [];
          for (let k = 0; k < n; k++) {
            const kind = w[i++];
            if (kind === REORDER_NEW) {
              const nw = w[i++];
              const holder = dom.fragment();
              buildRange(w, i, i + nw, holder);
              i += nw;
              const fresh = dom.childrenOf(holder)[0];
              placed.push({ node: fresh, move: true });
              collectPreorder(fresh, segNodes);
            } else {
              const pos = w[i++];
              const start = w[i++];
              const count = w[i++];
              used.add(pos);
              placed.push({ node: oldChildren[pos], move: kind === REORDER_MOVE });
              for (let t = start; t < start + count; t++) segNodes.push(refs[t]);
            }
          }
          splice = { at: parentIdx + 1, oldSpan, nodes: segNodes };
          for (let pos = 0; pos < oldChildren.length; pos++) {
            if (!used.has(pos)) {
              cleanupSubtree(oldChildren[pos]);
              dom.removeChild(parent, oldChildren[pos]);
            }
          }
          // Right-to-left, inserting each MOVE/NEW before the node that ends
          // up after it; STAY nodes are already in relative order.
          let anchor = null;
          for (let k = n - 1; k >= 0; k--) {
            if (placed[k].move) dom.insertBefore(parent, placed[k].node, anchor);
            anchor = placed[k].node;
          }
        } else {
          throw new Error(`unknown patch op ${op} at word ${i - 1}`);
        }
      }
    }
    if (structural) {
      nodeList = (structuralOps === 1 && splice)
        ? nodeList.slice(0, splice.at).concat(splice.nodes, nodeList.slice(splice.at + splice.oldSpan))
        : preorder();
    }
  }

  // Copy a JS string into wasm memory via the host's js_alloc; returns [ptr, len].
  function writeString(s) {
    const bytes = encoder.encode(s);
    return writeBytes(bytes);
  }

  function writeBytes(bytes) {
    if (bytes.length === 0) return [0, 0];
    const ptr = exports.js_alloc(bytes.length);
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    return [ptr, bytes.length];
  }

  // Console messages queue host-side (the module is import-free, so the
  // host cannot call out); drain them after every entry call. Each entry is
  // a (ptr, len, level) triple: level 0 is a Console.log message and goes
  // to console.log, level 1 is a compiler `dbg` message and goes to
  // console.debug (the Verbose level in devtools).
  function drainLog() {
    const n = exports.log_len();
    if (n > 0) {
      const w = new Uint32Array(memory.buffer, exports.log_ptr(), n);
      for (let i = 0; i + 2 < n; i += 3) {
        const msg = str(w[i], w[i + 1]);
        if (w[i + 2] === 1) console.debug(msg);
        else console.log(msg);
      }
      exports.log_clear();
    }
  }

  // Commands (async effects) queue host-side the same way. Parse them fully,
  // decoding strings and copying body bytes out of wasm memory, BEFORE
  // running anything, because executing them (js_alloc, dispatch_*) may grow
  // wasm memory and detach the views.
  function parseEffects() {
    const n = exports.effects_len();
    if (n === 0) return [];
    const w = new Uint32Array(memory.buffer, exports.effects_ptr(), n);
    const effects = [];
    let i = 0;
    while (i < n) {
      const kind = w[i++];
      if (kind === 1) { // HTTP
        const cb = w[i++];
        const method = str(w[i++], w[i++]);
        const url = str(w[i++], w[i++]);
        const bodyPtr = w[i++], bodyLen = w[i++];
        const body = bodyLen > 0 ? new Uint8Array(memory.buffer, bodyPtr, bodyLen).slice() : null;
        const timeoutMs = w[i++] + w[i++] * 4294967296; // u64 as lo, hi
        const headers = {};
        let nHeaders = w[i++];
        while (nHeaders-- > 0) headers[str(w[i++], w[i++])] = str(w[i++], w[i++]);
        effects.push({ kind: 'http', cb, method, url, body, timeoutMs, headers });
      } else if (kind === 2) { // AFTER (one-shot)
        effects.push({ kind: 'after', cb: w[i++], ms: w[i++] });
      } else if (kind === 8) { // SUB START
        effects.push({ kind: 'subStart', id: w[i++], ms: w[i++] });
      } else if (kind === 9) { // SUB STOP
        effects.push({ kind: 'subStop', id: w[i++] });
      } else if (kind === 10) { // KEYBOARD START
        const id = w[i++];
        const preventDefault = w[i++] !== 0;
        const event = str(w[i++], w[i++]);
        const keys = [];
        let nKeys = w[i++];
        while (nKeys-- > 0) keys.push(str(w[i++], w[i++]));
        effects.push({ kind: 'keyboardStart', id, preventDefault, event, keys });
      } else if (kind === 11) { // PORT SEND
        effects.push({ kind: 'portSend', name: str(w[i++], w[i++]), value: str(w[i++], w[i++]) });
      } else if (kind === 12) { // PORT LISTEN START (a subscription)
        effects.push({ kind: 'portStart', id: w[i++], name: str(w[i++], w[i++]) });
      } else if (kind === 13) { // URL CHANGE START (a subscription)
        effects.push({ kind: 'urlStart', id: w[i++] });
      } else if (kind === 14 || kind === 15) { // SHOW / CLOSE MODAL
        effects.push({ kind: kind === 14 ? 'showModal' : 'closeModal', selector: str(w[i++], w[i++]) });
      } else if (kind === 16) { // DEBOUNCE (keyed one-shot timer)
        effects.push({ kind: 'debounce', cb: w[i++], ms: w[i++], key: str(w[i++], w[i++]) });
      } else if (kind === 17) { // TIME CANCEL (discard a pending debounce)
        effects.push({ kind: 'timeCancel', key: str(w[i++], w[i++]) });
      } else if (kind === 18) { // HTTP FILE (file-body request)
        const cb = w[i++];
        const method = str(w[i++], w[i++]);
        const url = str(w[i++], w[i++]);
        const fileId = w[i++];
        const start = w[i++] + w[i++] * 4294967296; // u64 as lo, hi
        const len = w[i++] + w[i++] * 4294967296;
        const timeoutMs = w[i++] + w[i++] * 4294967296;
        const headers = {};
        let nHeaders = w[i++];
        while (nHeaders-- > 0) headers[str(w[i++], w[i++])] = str(w[i++], w[i++]);
        effects.push({ kind: 'httpFile', cb, method, url, fileId, start, len, timeoutMs, headers });
      } else if (kind === 19) { // CRYPTO DIGEST (hash bytes)
        const cb = w[i++];
        const algorithm = str(w[i++], w[i++]);
        const dataPtr = w[i++], dataLen = w[i++];
        const data = dataLen > 0 ? new Uint8Array(memory.buffer, dataPtr, dataLen).slice() : new Uint8Array();
        effects.push({ kind: 'cryptoDigest', cb, algorithm, data });
      } else if (kind === 20) { // CRYPTO DIGEST FILE (hash a file / slice)
        const cb = w[i++];
        const algorithm = str(w[i++], w[i++]);
        const fileId = w[i++];
        const start = w[i++] + w[i++] * 4294967296;
        const len = w[i++] + w[i++] * 4294967296;
        effects.push({ kind: 'cryptoDigestFile', cb, algorithm, fileId, start, len });
      } else if (kind === 5 || kind === 6 || kind === 7) { // NAVIGATION
        effects.push({ kind: ['navigate', 'pushUrl', 'replaceUrl'][kind - 5], url: str(w[i++], w[i++]) });
      } else {
        throw new Error(`unknown effect kind ${kind} at word ${i - 1}`);
      }
    }
    exports.effects_clear();
    return effects;
  }

  // False after unmount() or after a wasm trap. Async completions (fetch,
  // timers) can fire later; they must not re-enter a dead instance, and
  // after a trap or paint error the retained nodeList no longer matches the
  // DOM, so continuing would corrupt the page silently.
  let alive = true;

  // True while paint() applies patches, so DOM events the patching itself
  // fires synchronously (see setHandler) cannot re-enter the host.
  let painting = false;

  // Wall-clock ms spent inside enter() since mount, and how many times it
  // ran. This is the app's whole share of a frame (update, render, diff,
  // patch), so an embedder can put it next to the browser's own render
  // time and show where a slow frame actually goes (see www/perf.js, the
  // meter that reads these). Timing runs only while `enabled` is
  // set, which nothing does by default, so apps that never look at this pay
  // a branch per dispatch instead of two clock reads.
  // The phase counters stay 0 unless the wasm is a `joy_bench` build (which
  // exports bench_phase_ms). paintMs only needs `enabled`. All are cumulative
  // like busyMs, so a driver samples before/after and takes the difference.
  const perf = { enabled: false, busyMs: 0, entries: 0, updateMs: 0, renderMs: 0, diffMs: 0, paintMs: 0 };

  // Every call into the host goes through here: call, drain logs, paint if
  // the view changed, then start any queued effects (whose completions
  // re-enter through here as well).
  function enter(call) {
    if (!alive) return;
    const t0 = perf.enabled ? performance.now() : 0;
    try {
      const changed = call();
      drainLog();
      const effects = parseEffects();
      if (changed) {
        const p0 = perf.enabled ? performance.now() : 0;
        paint();
        if (perf.enabled) perf.paintMs += performance.now() - p0;
      }
      for (const e of effects) runEffect(e);
    } catch (err) {
      alive = false;
      throw err;
    } finally {
      if (perf.enabled) {
        perf.busyMs += performance.now() - t0;
        perf.entries += 1;
        if (exports.bench_phase_ms) {
          perf.updateMs += exports.bench_phase_ms(0);
          perf.renderMs += exports.bench_phase_ms(1);
          perf.diffMs += exports.bench_phase_ms(2);
        }
      }
    }
  }

  // Response headers as [name, value] pairs (names arrive lowercased from
  // the Headers object). Fetch stubs without a Headers object yield none.
  const respHeaders = (resp) => (resp.headers?.entries ? [...resp.headers.entries()] : []);

  // Run an http/httpFile effect's fetch. A timeout aborts the request and
  // reports sentinel status 1, any other network/body failure reports 0.
  // Real responses pass their status and headers through, whatever the
  // status (4xx/5xx included).
  function fetchHttp(e, body) {
    const opts = { method: e.method, headers: e.headers };
    if (body !== undefined && body !== null) opts.body = body;
    let timer = null;
    let timedOut = false;
    if (e.timeoutMs > 0) {
      const controller = new AbortController();
      opts.signal = controller.signal;
      timer = setTimeout(() => { timedOut = true; controller.abort(); }, e.timeoutMs);
    }
    // The failure arm must cover only the network/body phase: chaining a
    // .catch after the dispatch would call dispatchHttp a second time with
    // the same one-shot callback if the dispatch itself throws.
    fetch(e.url, opts)
      .then((resp) => resp.arrayBuffer().then((buf) => [resp.status, new Uint8Array(buf), respHeaders(resp)]))
      .then(
        ([status, body2, headers]) => { clearTimeout(timer); dispatchHttp(e.cb, status, body2, headers); },
        () => { clearTimeout(timer); dispatchHttp(e.cb, timedOut ? 1 : 0, new Uint8Array(), []); },
      );
  }

  function runEffect(e) {
    if (e.kind === 'http') {
      fetchHttp(e, e.body);
    } else if (e.kind === 'after') {
      setTimeout(() => dispatchTimer(e.cb, Date.now(), 1), e.ms); // one-shot: host releases the callback
    } else if (e.kind === 'subStart') {
      const handle = setInterval(() => dispatchSub(e.id, Date.now()), e.ms);
      subCleanups.set(e.id, () => clearInterval(handle));
    } else if (e.kind === 'keyboardStart') {
      // The key filter and preventDefault are subscription data, so they run
      // here without entering the app; they also form the sub's identity.
      const remove = dom.onGlobal(e.event, (domEvent) => {
        const info = dom.eventKeyInfo(domEvent);
        if (e.keys.length > 0 && !e.keys.includes(info.key)) return;
        if (e.preventDefault) domEvent.preventDefault?.();
        dispatchSubKey(e.id, info);
      });
      subCleanups.set(e.id, remove);
    } else if (e.kind === 'subStop') {
      subCleanups.get(e.id)?.();
      subCleanups.delete(e.id);
    } else if (e.kind === 'portStart') {
      ports.set(e.name, e.id);
      // A start for the same name can precede the old sub's stop in one
      // batch, so only forget the name if it still points at this sub.
      subCleanups.set(e.id, () => { if (ports.get(e.name) === e.id) ports.delete(e.name); });
    } else if (e.kind === 'urlStart') {
      subCleanups.set(e.id, dom.onUrlChange(() => dispatchSubValue(e.id, dom.currentUrl())));
    } else if (e.kind === 'portSend') {
      outPorts.get(e.name)?.(e.value); // unregistered names are a no-op
    } else if (e.kind === 'showModal') {
      dom.showModal(e.selector);
    } else if (e.kind === 'closeModal') {
      dom.closeModal(e.selector);
    } else if (e.kind === 'debounce') {
      dropDebounce(e.key); // re-arm: discard the pending timer and its callback
      const handle = setTimeout(() => {
        debounces.delete(e.key);
        dispatchTimer(e.cb, Date.now(), 1); // one-shot: host releases the callback
      }, e.ms);
      debounces.set(e.key, { handle, cb: e.cb });
    } else if (e.kind === 'timeCancel') {
      dropDebounce(e.key);
    } else if (e.kind === 'httpFile') {
      const file = files.get(e.fileId);
      if (!file) {
        dispatchHttp(e.cb, 0, new Uint8Array(), []); // unknown id = never completed
      } else {
        fetchHttp(e, sliceFile(file, e.start, e.len));
      }
    } else if (e.kind === 'cryptoDigest') {
      crypto.subtle.digest(e.algorithm, e.data).then(
        (buf) => dispatchBytes(e.cb, new Uint8Array(buf)),
        () => dispatchBytes(e.cb, new Uint8Array()), // empty hash = failure
      );
    } else if (e.kind === 'cryptoDigestFile') {
      const file = files.get(e.fileId);
      if (!file) {
        dispatchBytes(e.cb, new Uint8Array());
      } else {
        sliceFile(file, e.start, e.len)
          .arrayBuffer()
          .then((buf) => crypto.subtle.digest(e.algorithm, buf))
          .then(
            (buf) => dispatchBytes(e.cb, new Uint8Array(buf)),
            () => dispatchBytes(e.cb, new Uint8Array()),
          );
      }
    } else if (e.kind === 'navigate') {
      dom.navigate(e.url);
    } else if (e.kind === 'pushUrl') {
      dom.pushUrl(e.url);
    } else if (e.kind === 'replaceUrl') {
      dom.replaceUrl(e.url);
    }
  }

  // A file's byte range as a Blob: len 0 means through the end of the file.
  function sliceFile(file, start, len) {
    if (len > 0) return file.slice(start, start + len);
    return start > 0 ? file.slice(start) : file;
  }

  // Pack response headers for the host: a u32 count, then per header a u32
  // byte length + UTF-8 bytes for the name and the same for the value. The
  // host copies the strings out and frees the buffer. Returns 0 for none.
  function writeHeaders(headers) {
    if (headers.length === 0) return 0;
    const parts = headers.map(([name, value]) => [encoder.encode(name), encoder.encode(value)]);
    let size = 4;
    for (const [n, v] of parts) size += 8 + n.length + v.length;
    const ptr = exports.js_alloc(size);
    const view = new DataView(memory.buffer, ptr, size);
    const bytes = new Uint8Array(memory.buffer, ptr, size);
    let at = 0;
    view.setUint32(at, parts.length, true);
    at += 4;
    for (const [n, v] of parts) {
      view.setUint32(at, n.length, true);
      bytes.set(n, at + 4);
      at += 4 + n.length;
      view.setUint32(at, v.length, true);
      bytes.set(v, at + 4);
      at += 4 + v.length;
    }
    return ptr;
  }

  function dispatchHttp(cb, status, bodyBytes, headers) {
    const [ptr, len] = writeBytes(bodyBytes);
    const headersPtr = writeHeaders(headers);
    enter(() => exports.dispatch_http(cb, status, ptr, len, headersPtr));
  }

  function dispatchTimer(cb, nowMs, oneShot) {
    enter(() => exports.dispatch_timer(cb, nowMs, oneShot));
  }

  function dispatchSub(id, nowMs) {
    enter(() => exports.dispatch_sub(id, nowMs));
  }

  // Deliver a string to a port or URL-change subscription.
  function dispatchSubValue(id, value) {
    const [ptr, len] = writeString(value);
    enter(() => exports.dispatch_sub_value(id, ptr, len));
  }

  // Modifier/repeat booleans packed for the host (mirrored in its
  // key_event_args): 1 ctrl, 2 shift, 4 alt, 8 meta, 16 repeat,
  // 32 is_composing.
  const keyFlags = (i) =>
    (i.ctrl ? 1 : 0) | (i.shift ? 2 : 0) | (i.alt ? 4 : 0) | (i.meta ? 8 : 0) | (i.repeat ? 16 : 0) |
    (i.isComposing ? 32 : 0);

  function dispatchSubKey(id, info) {
    const [kp, kl] = writeString(info.key);
    const [cp, cl] = writeString(info.code);
    enter(() => exports.dispatch_sub_key(id, kp, kl, cp, cl, keyFlags(info)));
  }

  function dispatchKey(handlerId, info) {
    const [kp, kl] = writeString(info.key);
    const [cp, cl] = writeString(info.code);
    enter(() => exports.dispatch_key(handlerId, kp, kl, cp, cl, keyFlags(info)));
  }

  function dispatchPointer(handlerId, info) {
    enter(() => exports.dispatch_pointer(
      handlerId,
      info.clientX, info.clientY, info.pageX, info.pageY, info.offsetX, info.offsetY,
      info.button, info.buttons, keyFlags(info),
    ));
  }

  // Register the picked File under a fresh id and deliver its metadata; the
  // File itself stays here for Http.post_file / Crypto.digest_file.
  function dispatchFile(handlerId, file) {
    const id = nextFileId++;
    files.set(id, file);
    const [np, nl] = writeString(file.name ?? '');
    const [mp, ml] = writeString(file.type ?? '');
    enter(() => exports.dispatch_file(handlerId, id, np, nl, mp, ml, file.size ?? 0));
  }

  // Deliver hash bytes to a crypto digest's one-shot callback.
  function dispatchBytes(cb, bytes) {
    const [ptr, len] = writeBytes(bytes);
    enter(() => exports.dispatch_bytes(cb, ptr, len));
  }

  function dispatch(handlerId) {
    enter(() => exports.dispatch(handlerId));
  }

  function dispatchValue(handlerId, value) {
    const [ptr, len] = writeString(value);
    enter(() => exports.dispatch_value(handlerId, ptr, len));
  }

  // Deliver a value from JavaScript to a port the app listens on (see the
  // platform's Port module). Unknown names are a no-op.
  function sendPort(name, value) {
    const id = ports.get(name);
    if (id !== undefined) dispatchSubValue(id, String(value));
  }

  // Boot the app: the flags string is the only thing the pure `init`
  // receives, so the embedder writes any boot data the app needs (time,
  // url, whatever) into it. After boot the app gets its times from timer
  // messages and URL changes from its subscriptions.
  function start(flags = '') {
    const [fp, fl] = writeString(flags);
    enter(() => {
      exports.start(fp, fl);
      return true; // first render is always a paint
    });
  }

  // Register a JS handler for an outgoing port (Port.send in the app).
  // Registering a name again replaces the previous handler.
  function onPort(name, fn) {
    outPorts.set(name, fn);
  }

  // Stop everything that outlives a paint: subscription cleanups (intervals,
  // global key listeners), port registrations in both directions, and any
  // in-flight async completion (fetches, timers), which `alive` turns into
  // no-ops. The DOM is left as-is (the embedder owns the root).
  function unmount() {
    // Pending debounce timers are cleared (and their callbacks released)
    // while the instance is still alive, then `alive` turns any other
    // in-flight completion into a no-op.
    for (const key of [...debounces.keys()]) dropDebounce(key);
    alive = false;
    for (const cleanup of subCleanups.values()) cleanup();
    subCleanups.clear();
    ports.clear();
    outPorts.clear();
    files.clear();
  }

  return { start, dispatch, dispatchValue, sendPort, onPort, unmount, perf };
}

const MOUNT_OPTIONS = ['wasm', 'root', 'flags', 'dom', 'setup'];

// Start an app and return a handle on it.
//
//   wasm   a URL to fetch, or the module's bytes
//   root   the element to render into
//   flags  the string handed to the app's `init`, "" when it has no use for
//          one. Required because the Roc side has no default either: every
//          `init : Str -> ...` receives something, so the page always says what.
//   dom    the DOM adapter, browser by default. The Node harnesses pass a fake
//          one to drive an app with no browser around.
//   setup  runs before the app starts, so outgoing-port handlers can be
//          registered in time to receive sends from `init`.
export async function mount(options) {
  const { wasm, root, flags, dom = browserDom, setup = null } = options ?? {};

  // Named options make a typo silent by default, and each of these would fail
  // far from its cause: a misspelled `flags` looks like empty flags, and a
  // misspelled `dom` quietly mounts a test into the real document.
  for (const key of Object.keys(options ?? {})) {
    if (!MOUNT_OPTIONS.includes(key)) {
      throw new TypeError(`mount: unknown option \`${key}\`, expected ${MOUNT_OPTIONS.join(', ')}`);
    }
  }
  if (wasm == null) throw new TypeError('mount: `wasm` is required, a URL to fetch or the module bytes');
  if (root == null) throw new TypeError('mount: `root` is required, the element to render into');
  if (typeof flags !== 'string') throw new TypeError('mount: `flags` is required, the string passed to init ("" when unused)');

  const instance = await instantiate(wasm);
  const rt = makeRuntime(instance.exports, dom, root);
  const app = { instance, dispatch: rt.dispatch, dispatchValue: rt.dispatchValue, sendPort: rt.sendPort, onPort: rt.onPort, unmount: rt.unmount, perf: rt.perf };
  setup?.(app);
  rt.start(flags);
  return app;
}

// A URL streams from the network straight into the compiler, which is faster
// than fetching the bytes first and saves every page the same three lines.
// Streaming only works when the server labels the response `application/wasm`
// though, and plenty of static hosts call it octet-stream, so check the header
// rather than compiling a fallback out of a failure.
async function instantiate(wasm) {
  // A normal host declares no imports and ignores this object entirely. A
  // `joy_bench` build (see host.rs) imports a clock to time its phases, and
  // providing it unconditionally keeps instantiation uniform.
  const imports = { env: { joy_bench_now: () => performance.now() } };
  if (typeof wasm !== 'string') {
    return WebAssembly.instantiate(await WebAssembly.compile(wasm), imports);
  }
  const res = await fetch(wasm);
  if (!res.ok) throw new Error(`mount: could not fetch ${wasm} (${res.status} ${res.statusText})`);
  if (res.headers.get('content-type')?.startsWith('application/wasm')) {
    return (await WebAssembly.instantiateStreaming(res, imports)).instance;
  }
  return WebAssembly.instantiate(await WebAssembly.compile(await res.arrayBuffer()), imports);
}

// Browser DOM adapter.
export const browserDom = {
  createElement: (tag) => document.createElement(tag),
  createText: (s) => document.createTextNode(s),
  fragment: () => document.createDocumentFragment(),
  append: (parent, child) => parent.appendChild(child),
  clear: (node) => { node.replaceChildren(); },
  on: (node, event, fn) => node.addEventListener(event, fn),
  setText: (node, s) => { node.nodeValue = s; },
  childrenOf: (node) => Array.from(node.childNodes),
  replaceNode: (oldNode, newNode) => oldNode.replaceWith(newNode),
  insertBefore: (parent, node, anchor) => parent.insertBefore(node, anchor),
  removeChild: (parent, node) => parent.removeChild(node),
  setAttr: (node, k, v) => {
    node.setAttribute(k, v);
    // Live form-control state follows the property, not the attribute: once
    // the user has interacted, the attribute only describes the default.
    if (k === 'value' && 'value' in node) node.value = v;
    else if (k === 'checked' && 'checked' in node) node.checked = true;
    else if (k === 'selected' && 'selected' in node) node.selected = true;
  },
  removeAttr: (node, k) => {
    node.removeAttribute(k);
    if (k === 'value' && 'value' in node) node.value = '';
    else if (k === 'checked' && 'checked' in node) node.checked = false;
    else if (k === 'selected' && 'selected' in node) node.selected = false;
  },
  // Read the named property off the event target, stringified; missing,
  // null and NaN read as "". Booleans arrive as "true"/"false", numbers as
  // their decimal text (see Attribute.on_property).
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
    button: e?.button > 0 ? e.button : 0, // pointermove reports -1
    buttons: e?.buttons ?? 0,
    ctrl: !!e?.ctrlKey,
    shift: !!e?.shiftKey,
    alt: !!e?.altKey,
    meta: !!e?.metaKey,
  }),
  // The first picked file, or null (clearing a file input fires change with
  // an empty file list).
  eventFile: (e) => e?.target?.files?.[0] ?? null,
  showModal: (selector) => {
    const el = document.querySelector(selector);
    if (el && typeof el.showModal === 'function' && !el.open) el.showModal();
  },
  closeModal: (selector) => {
    const el = document.querySelector(selector);
    if (el && typeof el.close === 'function' && el.open) el.close();
  },
  onGlobal: (event, fn) => {
    document.addEventListener(event, fn);
    return () => document.removeEventListener(event, fn);
  },
  navigate: (url) => location.assign(url),
  pushUrl: (url) => history.pushState(null, '', url),
  replaceUrl: (url) => history.replaceState(null, '', url),
  // popstate fires on window (it does not reach document listeners) and only
  // for user history navigation, not for pushState/replaceState above.
  onUrlChange: (fn) => {
    window.addEventListener('popstate', fn);
    return () => window.removeEventListener('popstate', fn);
  },
  currentUrl: () => location.pathname + location.search + location.hash,
  observeVisibility: (node, rootMargin, fire) => {
    const observer = new IntersectionObserver(
      (entries) => entries.forEach((entry) => { if (entry.isIntersecting) fire(); }),
      { rootMargin },
    );
    observer.observe(node);
    return () => observer.disconnect();
  },
};
