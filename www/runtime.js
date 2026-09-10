// Joy runtime: drive the WASM loop and paint its command buffer into the DOM.
//
// The host renders internally (start()/dispatch()/dispatch_value() fill the
// command buffer). The first paint is a full build, or, when mounted with
// `hydrate: true`, a claim walk over the server-rendered DOM (see "Hydration"
// below). Later paints are diffs: the host emits patch ops addressing nodes
// by their pre-order index, which the runtime tracks in a retained `nodeList`.
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
// Tag/attr/event names and attr values are srefs (interned string refs, see
// `sref` below). Text content and key filters are raw (ptr, len) pairs.
// Patch ops:
//   SET_TEXT(5) idx str | REPLACE(6) idx n_words <build ops...>
//   PATCH_ATTRS(10) idx n_words <attr ops...>, a host-computed diff whose
//     ops also include REMOVE_ATTR(17) key | REMOVE_EVENT(18) name |
//     REMOVE_VIS(19). Removal names are embedded in the buffer (len word +
//     packed bytes), not (ptr, len) references
//   REORDER(12) parent_idx old_span n_children n_kept <descriptors...>, which
//     rewrites a child list. One descriptor per child of the new list, in order:
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
const OP_REMOVE_ATTR = 17;
const OP_REMOVE_EVENT = 18;
const OP_REMOVE_VIS = 19;
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
//   elementTag(node) -> tag | null ; getAttr(node, k) -> string | null
//   getProp(node, k) ; setProp(node, k, v) ; radioGroup(node) -> node[]
// Hydration additionally needs (only checked when `hydrate` is set):
//   textValue(node) -> string | null
//   splitText(textNode, offset) -> the new following text node
//   clearParsedTemplate(node), optional (see hydrateRange)
export function makeRuntime(exports, dom, root, hydrate = false) {
  const { memory } = exports;
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let nodeList = []; // DOM nodes in pre-order, matching the host's node indices

  // Armed by mount({hydrate: true}) and spent on the first full paint: that
  // one paint claims the server-rendered nodes instead of building fresh
  // ones. A later MODE_FULL (there is none today) would rebuild normally.
  let hydrateFirstPaint = !!hydrate;
  // The adapter methods that only some paths reach are checked up front,
  // so a custom adapter fails at mount rather than at the first event
  // (restoreControl) or the first claim.
  const needed = ['elementTag', 'getAttr', 'getProp', 'setProp', 'radioGroup'];
  if (hydrate) needed.push('textValue', 'splitText');
  for (const m of needed) {
    if (typeof dom[m] !== 'function') {
      throw new TypeError(`mount: the dom adapter needs ${m}(), see the \`dom\` interface notes`);
    }
  }

  // True while hydrateRange claims nodes. applyAttrOps reads it to skip
  // attribute writes the server-rendered markup already carries.
  let claiming = false;

  // The first repair hydrateRange had to make, kept for one console.warn
  // after the walk: a mismatch means the server and the client disagree
  // about the first render, which the page recovers from (the mismatched
  // nodes are rebuilt) but the developer should hear about.
  let hydrateMismatch = null;
  const noteMismatch = (what) => { hydrateMismatch ??= what; };

  // The walk's outcome, readable through the app handle's hydration() so a
  // test or a monitor can assert on it instead of scraping the console:
  // null until the claim walk has run (always, without `hydrate`), then
  // { claimed, mismatch }. `claimed` is false when the root was empty and
  // the walk was a plain build; `mismatch` repeats the warning's cause, or
  // null for a clean claim.
  let hydrateOutcome = null;

  const words = () => new Uint32Array(memory.buffer, exports.cmd_ptr(), exports.cmd_len());

  // One persistent view over the whole linear memory, refreshed when a
  // memory.grow detaches it (the old buffer's views read as length 0). The
  // memory.buffer getter and a fresh subview per string are real costs at
  // this call rate.
  let memU8 = new Uint8Array(memory.buffer);
  const mem = () => {
    if (memU8.byteLength === 0) memU8 = new Uint8Array(memory.buffer);
    return memU8;
  };

  // Most protocol strings are short (tags, attribute names, row-sized text),
  // and TextDecoder's per-call overhead dwarfs the decode at those sizes, so
  // short ASCII runs decode by hand and only long or non-ASCII strings pay
  // for the decoder.
  const str = (ptr, len) => {
    const m = mem();
    if (len > 64) return decoder.decode(m.subarray(ptr, ptr + len));
    let out = '';
    for (let i = 0; i < len; i++) {
      const b = m[ptr + i];
      if (b > 0x7f) return decoder.decode(m.subarray(ptr, ptr + len));
      out += String.fromCharCode(b);
    }
    return out;
  };

  // Interned protocol strings by host-assigned id. Tag/attribute/event names
  // and attribute values arrive as "srefs": [0, ptr, len] raw, [id<<2|1] a
  // known id, [id<<2|3, ptr, len] a new id to decode once and remember. The
  // decoded string lands in `srefVal` and the call returns the next word
  // index, so the hot path allocates nothing.
  const strings = [];
  let srefVal = '';
  function sref(w, i) {
    const head = w[i++];
    const tag = head & 3;
    if (tag === 1) {
      srefVal = strings[head >> 2];
      return i;
    }
    const s = str(w[i++], w[i++]);
    if (tag === 3) strings[head >> 2] = s;
    srefVal = s;
    return i;
  }

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

  // Per-node handler bookkeeping. Attribute state needs no record here: the
  // host diffs the attribute lists itself and PATCH_ATTRS arrives as precise
  // set/remove ops. Event listeners are bound once per (node, event) and
  // look their current handler up here, so re-renders never re-bind. A
  // removed handler leaves a null tombstone (the DOM listener stays attached
  // but inert), which stops a later re-add from binding a second listener.
  // An expando symbol rather than a WeakMap: property access is several
  // times cheaper, and create-heavy paints hit this per handler element.
  const EVENTS = Symbol('joyEvents'); // node[EVENTS]: Map(name -> {kind, id, ...} | null)
  const eventsFor = (node) => (node[EVENTS] ??= new Map());
  // The boolean live props the view declares on a node, recorded as their
  // attribute ops are applied: node[LIVE] = {checked, selected} holding the
  // declared true/false. A declared-false checkbox and one the view never
  // mentions look the same in the DOM (no attribute), and only the declared
  // one may be pinned back by restoreControl.
  const LIVE = Symbol('joyLive');

  // After an event from `node`, pin its live properties back to what the
  // view declares. The differ writes `value`, `checked` and `selected` only
  // when the view changes them, while typing and clicking change the DOM
  // property without touching the view. So a dispatch whose update rejects
  // the input, leaving the view as it was, would otherwise leave the
  // property showing what the model refused. The `value` attribute is the
  // view's truth (setAttr writes both), the bool props come from node[LIVE].
  // Writes happen only on drift: the common accepted keystroke, whose
  // render already wrote the new value, costs a read here. A write keeps
  // the caret where the user had it (see writeValue in browserDom). A
  // radio's group-mates and a select's options change state
  // without an event of their own, so they are pinned with the element
  // that fired. Running after the dispatch, this also covers inputs inside
  // a lazy region the render skipped.
  const CONTROLS = new Set(['input', 'textarea', 'select']);
  function pinProp(node, k, want) {
    if (dom.getProp(node, k) !== want) dom.setProp(node, k, want);
  }
  function pinChecked(node) {
    const declared = node[LIVE]?.checked;
    if (declared !== undefined) pinProp(node, 'checked', declared);
  }
  function pinOptions(node) {
    for (const c of dom.childrenOf(node)) {
      const declared = c[LIVE]?.selected;
      if (declared !== undefined) pinProp(c, 'selected', declared);
      else if (dom.elementTag(c) === 'optgroup') pinOptions(c);
    }
  }
  function restoreControl(node) {
    const tag = dom.elementTag(node);
    if (!CONTROLS.has(tag)) return;
    const value = dom.getAttr(node, 'value');
    if (value !== null) pinProp(node, 'value', value);
    if (tag === 'input') {
      pinChecked(node);
      if (node[LIVE]?.checked !== undefined && dom.getAttr(node, 'type') === 'radio') {
        for (const mate of dom.radioGroup(node)) if (mate !== node) pinChecked(mate);
      }
    } else if (tag === 'select') {
      pinOptions(node);
    }
  }
  // Visibility observers are rare, so their state lives off to the side
  // instead of widening every node's record.
  const nodeVis = new WeakMap(); // node -> { margin, key, id, disconnect }

  // Live visibility observers. cleanupSubtree exists only to disconnect
  // these, and most apps never use on_visible, so the count lets every
  // discard-time subtree walk be skipped outright.
  let visCount = 0;

  // Attach or re-arm a visibility observer. A fresh observer reports the
  // current intersection state, so recreating it when the rearm key changes
  // re-checks visibility (see Attribute.on_visible in the platform).
  function setVisibility(node, margin, key, id) {
    const v = nodeVis.get(node);
    if (v && v.margin === margin && v.key === key) {
      v.id = id; // same observer, refreshed handler
      return;
    }
    if (v) { v.disconnect(); visCount--; }
    const disconnect = dom.observeVisibility(node, margin, () => {
      const cur = nodeVis.get(node);
      if (cur) dispatch(cur.id);
    });
    nodeVis.set(node, { margin, key, id, disconnect });
    visCount++;
  }

  // The one listener function every binding shares: the node and event name
  // arrive as currentTarget and type, so binding allocates no closure.
  const domListener = (domEvent) => {
    // Patching the DOM can itself fire events synchronously: hiding or
    // removing a focused element fires blur before the patch finishes.
    // Dispatching mid-paint would re-enter the host against a nodeList
    // that no longer matches the DOM (and a handler id the host already
    // dropped), corrupting the page. Such events are echoes of the state
    // change being painted, so they are dropped, not deferred.
    if (painting) return;
    const d = domEvent.currentTarget[EVENTS]?.get(domEvent.type);
    if (!d) return; // handler was removed by a later patch
    // Stopping propagation is about this element swallowing the event, not
    // about which msg it produces, so it runs before any per-kind work and
    // independently of preventDefault. preventDefault stays per-kind
    // because a key handler's filter must run first: an unmatched key
    // passes through with its browser default intact. Every handler kind
    // carries both flags except file, where they read as undefined.
    if (d.stopPropagation) domEvent.stopPropagation?.();
    const node = domEvent.currentTarget;
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
      return; // a file input's value is the pick itself, never pinned
    } else {
      if (d.preventDefault) domEvent.preventDefault?.();
      dispatchValue(d.id, dom.eventProp(domEvent, d.prop));
      // Text under IME composition is provisional, and writing the property
      // would end the composition, so the pin waits for compositionend
      // (bound next to every on_input, see setHandler). Whichever order the
      // engine fires the two in, the last of them runs the pin against the
      // final text.
      if (domEvent.isComposing) return;
    }
    restoreControl(node);
  };
  // Engines disagree on the order at the end of a composition. Chromium
  // fires the last `input` (isComposing) before compositionend. Firefox
  // fires compositionend first and the `input` carrying the text after it.
  // Firefox's own IME typing still fires `input` with isComposing during
  // the composition, while Playwright's fill on Firefox takes the same
  // ending with no `input` during the composition at all, which is what
  // the e2e suite drives. Pinning first would revert text the app has not
  // seen, so the composed value is delivered through the input handler
  // here and pinned after. Where the input came first the value is
  // already in the model and the delivery changes nothing, and the
  // trailing Firefox input then carries the settled value.
  const compositionListener = (domEvent) => {
    if (painting) return;
    const node = domEvent.currentTarget;
    const d = node[EVENTS]?.get('input');
    if (d?.kind === 'value') dispatchValue(d.id, dom.eventProp({ target: node }, d.prop));
    restoreControl(node);
  };

  function setHandler(node, name, desc) {
    const m = eventsFor(node);
    if (!m.has(name)) {
      dom.on(node, name, domListener);
      if (name === 'input' && desc.kind === 'value') dom.on(node, 'compositionend', compositionListener);
    }
    m.set(name, desc);
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

  // Read a string embedded in the command buffer itself at word index `i`
  // (a length word, then the bytes packed four per word). Returns [string,
  // next word index]. Removal ops embed their names because the tree those
  // names lived in is dropped before the paint runs.
  function inlineStr(w, i) {
    const len = w[i++];
    const s = str(exports.cmd_ptr() + i * 4, len);
    return [s, i + ((len + 3) >> 2)];
  }

  // Apply the attr-op range [i, end) to `node`; returns the next index.
  // Sets and removals arrive exactly as needed (the host diffs the
  // attribute lists), so nothing is recorded about plain attributes.
  function applyAttrOps(w, i, end, node) {
    while (i < end) {
      const op = w[i++];
      if (op === OP_ATTR) {
        i = sref(w, i);
        const k = srefVal;
        i = sref(w, i);
        const v = srefVal;
        // A refused value also drops whatever the attribute held before:
        // keeping a stale href would leave the link pointing somewhere the
        // view no longer says.
        //
        // While claiming, a value the markup already carries is not
        // rewritten. Beyond saving the write, this leaves live form-control
        // state alone: setAttr('value') also sets the property, and the
        // user may have typed into the field before the app booted.
        if (attrAllowed(k, v)) {
          if (!claiming || dom.getAttr(node, k) !== v) dom.setAttr(node, k, v);
        } else dom.removeAttr(node, k);
      } else if (op === OP_BOOL_ATTR) {
        i = sref(w, i);
        const k = srefVal;
        const flag = w[i++] !== 0;
        if (k === 'checked' || k === 'selected') (node[LIVE] ??= {})[k] = flag;
        // Bare boolean attributes parse to "", which is also what setAttr
        // writes, so presence is the whole comparison while claiming.
        if (flag && attrAllowed(k, '')) {
          if (!claiming || dom.getAttr(node, k) == null) dom.setAttr(node, k, '');
        } else if (!claiming || dom.getAttr(node, k) != null) dom.removeAttr(node, k);
      } else if (op === OP_MSG_EVENT) {
        i = sref(w, i);
        const name = srefVal;
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'msg', preventDefault, stopPropagation, id: w[i++] });
      } else if (op === OP_VALUE_EVENT) {
        i = sref(w, i);
        const name = srefVal;
        i = sref(w, i);
        const prop = srefVal;
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'value', prop, preventDefault, stopPropagation, id: w[i++] });
      } else if (op === OP_KEY_EVENT) {
        i = sref(w, i);
        const name = srefVal;
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        const id = w[i++];
        const keys = [];
        let nKeys = w[i++];
        while (nKeys-- > 0) keys.push(str(w[i++], w[i++]));
        setHandler(node, name, { kind: 'key', preventDefault, stopPropagation, keys, id });
      } else if (op === OP_POINTER_EVENT) {
        i = sref(w, i);
        const name = srefVal;
        const preventDefault = w[i++] !== 0;
        const stopPropagation = w[i++] !== 0;
        setHandler(node, name, { kind: 'pointer', preventDefault, stopPropagation, id: w[i++] });
      } else if (op === OP_FILE_EVENT) {
        setHandler(node, 'change', { kind: 'file', id: w[i++] });
      } else if (op === OP_VISIBLE) {
        i = sref(w, i);
        const margin = srefVal;
        i = sref(w, i);
        const key = srefVal;
        setVisibility(node, margin, key, w[i++]);
      } else if (op === OP_REMOVE_ATTR) {
        let k;
        [k, i] = inlineStr(w, i);
        dom.removeAttr(node, k);
        if (node[LIVE] !== undefined) node[LIVE][k] = undefined; // no longer declared
      } else if (op === OP_REMOVE_EVENT) {
        let name;
        [name, i] = inlineStr(w, i);
        // Tombstone, not delete: the DOM listener stays attached, and the
        // null is what tells a later re-add it must not bind a second one.
        const m = node[EVENTS];
        if (m && m.has(name)) m.set(name, null);
      } else if (op === OP_REMOVE_VIS) {
        const v = nodeVis.get(node);
        if (v) { v.disconnect(); nodeVis.delete(node); visCount--; }
      } else {
        return i - 1; // not an attr op: caller resumes here
      }
    }
    return i;
  }

  // Build the balanced op range [start, end) into `parent` and return the next
  // index. Nodes are created in document pre-order, so when `out` is given
  // every created node is pushed onto it, saving callers that need the
  // subtree's pre-order (the node-list splice) a second walk.
  function buildRange(w, start, end, parent, out) {
    const stack = [parent];
    const top = () => stack[stack.length - 1];
    let i = start;
    while (i < end) {
      const op = w[i];
      if (op === OP_ELEMENT_OPEN) {
        i = sref(w, i + 1);
        const el = dom.createElement(srefVal);
        dom.append(top(), el);
        out?.push(el);
        stack.push(el);
      } else if (op === OP_ELEMENT_CLOSE) {
        i += 1;
        stack.pop();
      } else if (op === OP_TEXT) {
        i += 1;
        const t = dom.createText(str(w[i++], w[i++]));
        dom.append(top(), t);
        out?.push(t);
      } else if (op === OP_ATTR || op === OP_BOOL_ATTR || op === OP_MSG_EVENT || op === OP_VALUE_EVENT || op === OP_KEY_EVENT || op === OP_POINTER_EVENT || op === OP_FILE_EVENT || op === OP_VISIBLE) {
        i = applyAttrOps(w, i, end, top());
      } else {
        throw new Error(`unknown build op ${op} at word ${i}`);
      }
    }
    return i;
  }

  // --- Hydration ---
  //
  // Claim the server-rendered DOM instead of building it: walk the same
  // balanced build-op range a full build would execute, but advance a cursor
  // through the existing children in lockstep, adopting each node the ops
  // expect. Handlers attach and handler ids record exactly as in a build;
  // attribute values the markup already carries are skipped (see
  // applyAttrOps). The result must be indistinguishable from a fresh build,
  // node for node, because every later patch addresses nodes by pre-order
  // index, so the walk also fixes what HTML serialization cannot express:
  //
  //   * adjacent text vnodes serialize as one merged text node, so the DOM
  //     node is split and the front claimed (splitText)
  //   * empty text vnodes serialize as nothing, so an empty text node is
  //     inserted where the ops expect one
  //   * comments (and anything else that is neither element nor text) never
  //     came from a view, so they are dropped on sight
  //
  // A genuine mismatch, where the markup disagrees with the app's first
  // render, is repaired locally: the expected node is built fresh in place,
  // its whole subtree with it (a frame with kids === null builds fresh
  // without further matching), and children the ops never claimed are
  // removed when their parent closes. The page always ends up showing the
  // app's own render; the first repair is remembered and warned once,
  // because the fix belongs on the server.
  function hydrateRange(w, start, end) {
    // One frame per open element: the element and a cursor (kids, idx) into
    // its pre-existing children. Fresh (repaired) elements carry kids ===
    // null, so their subtrees skip matching entirely. An empty root gets the
    // fresh treatment from the start: nothing was server-rendered, which is
    // a plain build and not a mismatch, so one loader serves both cases.
    const rootKids = [...dom.childrenOf(root)];
    const hadKids = rootKids.length !== 0; // the walk splices rootKids, so decide now
    const frames = [{ parent: root, kids: hadKids ? rootKids : null, idx: 0 }];
    const top = () => frames[frames.length - 1];

    // Remove comment-ish nodes at the cursor: neither element nor text, so
    // no view produced them and no op will ever claim them.
    const dropJunk = (f) => {
      let cand = f.kids[f.idx];
      while (cand !== undefined && dom.elementTag(cand) === null && dom.textValue(cand) === null) {
        dom.removeChild(f.parent, cand);
        f.kids.splice(f.idx, 1);
        cand = f.kids[f.idx];
      }
    };

    // Put a freshly built node where the cursor stands. It is claimed by
    // construction and never enters `kids`, so the leftover sweep in
    // closeFrame cannot touch it.
    const insertFresh = (f, node) => {
      dom.insertBefore(f.parent, node, f.kids === null ? null : f.kids[f.idx] ?? null);
    };

    // Children the ops never claimed are not in the app's first render:
    // remove them. Elements and text are real divergence worth the warning;
    // stray junk is not.
    const closeFrame = (f) => {
      if (f.kids === null) return;
      for (let k = f.idx; k < f.kids.length; k++) {
        if (dom.elementTag(f.kids[k]) !== null || dom.textValue(f.kids[k]) !== null) {
          noteMismatch(`the server rendered more inside <${dom.elementTag(f.parent) ?? 'the root'}> than the app's first render has`);
        }
        dom.removeChild(f.parent, f.kids[k]);
      }
    };

    const hydrateText = (f, s) => {
      if (f.kids !== null) {
        dropJunk(f);
        const cand = f.kids[f.idx];
        const t = cand === undefined ? null : dom.textValue(cand);
        if (t !== null) {
          if (t === s) {
            f.idx++;
            return;
          }
          if (s.length < t.length && t.startsWith(s)) {
            // The serializer merged this vnode with the text after it: cut
            // ours off the front and leave the rest for the next op. Also
            // covers an expected-empty text in front of a real one
            // (splitText at 0).
            const rest = dom.splitText(cand, s.length);
            f.kids.splice(f.idx + 1, 0, rest);
            f.idx++;
            return;
          }
          if (s.length > 0) {
            noteMismatch(`expected the text ${JSON.stringify(s)} but the server rendered ${JSON.stringify(t)}`);
            dom.setText(cand, s);
            f.idx++;
            return;
          }
        }
        if (s.length > 0) noteMismatch(`expected the text ${JSON.stringify(s)}`);
      }
      // Nothing claimable here: the vnode is empty text (which HTML cannot
      // express), the tree diverged, or this subtree is fresh anyway.
      insertFresh(f, dom.createText(s));
    };

    let i = start;
    while (i < end) {
      const op = w[i];
      if (op === OP_ELEMENT_OPEN) {
        i = sref(w, i + 1);
        const tag = srefVal;
        const f = top();
        let el = null;
        if (f.kids !== null) {
          dropJunk(f);
          const cand = f.kids[f.idx];
          // Case-insensitive: HTML tags parse caselessly, and SVG localName
          // keeps camelCase (feGaussianBlur) while views may not.
          if (cand !== undefined && dom.elementTag(cand)?.toLowerCase() === tag.toLowerCase()) {
            el = cand;
            f.idx++;
          } else if (cand !== undefined) {
            noteMismatch(`expected <${tag}> but the server rendered ${dom.elementTag(cand) === null ? 'text' : `<${dom.elementTag(cand)}>`}`);
          } else {
            noteMismatch(`expected <${tag}> but the server rendered nothing there`);
          }
        }
        if (el !== null) {
          // The parser moves a template's children into its inert
          // `.content` fragment; the ops build them as regular children
          // (like createElement does), so the parsed copies would linger
          // unseen. Dropping them keeps one copy.
          dom.clearParsedTemplate?.(el);
          frames.push({ parent: el, kids: [...dom.childrenOf(el)], idx: 0 });
        } else {
          const fresh = dom.createElement(tag);
          insertFresh(f, fresh);
          frames.push({ parent: fresh, kids: null, idx: 0 });
        }
      } else if (op === OP_ELEMENT_CLOSE) {
        i += 1;
        closeFrame(frames.pop());
      } else if (op === OP_TEXT) {
        const s = str(w[i + 1], w[i + 2]);
        i += 3;
        hydrateText(top(), s);
      } else if (op === OP_ATTR || op === OP_BOOL_ATTR || op === OP_MSG_EVENT || op === OP_VALUE_EVENT || op === OP_KEY_EVENT || op === OP_POINTER_EVENT || op === OP_FILE_EVENT || op === OP_VISIBLE) {
        i = applyAttrOps(w, i, end, top().parent);
      } else {
        throw new Error(`unknown build op ${op} at word ${i}`);
      }
    }
    closeFrame(frames.pop()); // the root's own leftovers
    return hadKids; // whether there was server-rendered DOM to claim
  }

  // Disconnect visibility observers in a subtree that is about to be
  // discarded (full rebuild or REPLACE), so they cannot fire or leak. When
  // no observer is live anywhere, the walk is skipped entirely.
  function cleanupSubtree(node) {
    if (visCount === 0) return;
    cleanupVisWalk(node);
  }

  function cleanupVisWalk(node) {
    const v = nodeVis.get(node);
    if (v) { v.disconnect(); nodeVis.delete(node); visCount--; }
    for (const c of dom.childrenOf(node)) cleanupVisWalk(c);
  }

  // Pre-order list of the DOM nodes under `root` (root itself excluded).
  function preorder() {
    const out = [];
    const visit = (n) => { out.push(n); for (const c of dom.childrenOf(n)) visit(c); };
    for (const c of dom.childrenOf(root)) visit(c);
    return out;
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
      if (hydrateFirstPaint) {
        hydrateFirstPaint = false;
        claiming = true;
        let claimed = false;
        try {
          claimed = hydrateRange(w, 1, w.length);
        } finally {
          claiming = false;
        }
        hydrateOutcome = { claimed, mismatch: hydrateMismatch };
        if (hydrateMismatch) {
          console.warn(`Joy hydrate: the server-rendered HTML did not match the app's first render (${hydrateMismatch}). The mismatched nodes were rebuilt, so the page is correct, but the server view and the client's init disagree and hydration paid for both.`);
        }
      } else {
        cleanupSubtree(root);
        dom.clear(root);
        buildRange(w, 1, w.length, root);
      }
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
          applyAttrOps(w, i, i + n, refs[idx]);
          i += n;
        } else if (op === OP_REFRESH_HANDLERS) {
          // The element's attributes are unchanged except that its handlers
          // were re-boxed by the render (they always are), so only the stored
          // handler ids move, with no attribute writes and no listener
          // rebinding.
          const m = eventsFor(refs[w[i++]]);
          const n = w[i++];
          for (let k = 0; k < n; k++) {
            i = sref(w, i);
            const d = m.get(srefVal);
            const id = w[i++];
            if (d) d.id = id;
          }
        } else if (op === OP_REORDER) {
          structural = true;
          structuralOps += 1;
          const parentIdx = w[i++];
          const oldSpan = w[i++];
          const parent = refs[parentIdx];
          const n = w[i++];
          const kept = w[i++];
          const segNodes = [];
          if (kept === 0) {
            // No old child survives: drop them all at once and rebuild into
            // the emptied parent, where append order is document order. This
            // is the clear and replace-all shape, and it skips the per-node
            // removals and inserts of the general path entirely.
            if (visCount > 0) for (const c of dom.childrenOf(parent)) cleanupVisWalk(c);
            dom.clear(parent);
            for (let k = 0; k < n; k++) {
              i++; // kind is always NEW here
              const nw = w[i++];
              buildRange(w, i, i + nw, parent, segNodes);
              i += nw;
            }
          } else {
            const oldChildren = [...dom.childrenOf(parent)];
            // Resolve every descriptor to a node first (building NEW
            // subtrees), so old positions are read before the DOM mutates.
            // segNodes accumulates the segment's new pre-order for the
            // splice.
            const placed = [];
            const moved = [];
            const used = new Uint8Array(oldChildren.length);
            for (let k = 0; k < n; k++) {
              const kind = w[i++];
              if (kind === REORDER_NEW) {
                const nw = w[i++];
                const holder = dom.fragment();
                const fresh = [];
                buildRange(w, i, i + nw, holder, fresh);
                i += nw;
                placed.push(fresh[0]);
                moved.push(true);
                for (const node of fresh) segNodes.push(node);
              } else {
                const pos = w[i++];
                const start = w[i++];
                const count = w[i++];
                used[pos] = 1;
                placed.push(oldChildren[pos]);
                moved.push(kind === REORDER_MOVE);
                for (let t = start; t < start + count; t++) segNodes.push(refs[t]);
              }
            }
            for (let pos = 0; pos < oldChildren.length; pos++) {
              if (!used[pos]) {
                cleanupSubtree(oldChildren[pos]);
                dom.removeChild(parent, oldChildren[pos]);
              }
            }
            // Right-to-left, inserting each MOVE/NEW before the node that
            // ends up after it. STAY nodes are already in relative order.
            let anchor = null;
            for (let k = n - 1; k >= 0; k--) {
              if (moved[k]) dom.insertBefore(parent, placed[k], anchor);
              anchor = placed[k];
            }
          }
          splice = { at: parentIdx + 1, oldSpan, nodes: segNodes };
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
      } else if (kind === 21) { // FOCUS
        effects.push({ kind: 'focus', selector: str(w[i++], w[i++]) });
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

  const overflowError = () =>
    new Error('Joy: the wasm shadow stack overflowed and memory is corrupt. The usual cause is unbounded recursion in update or render, or a view nested far deeper than any browser renders well.');

  // Every call into the host goes through here: call, drain logs, paint if
  // the view changed, then start any queued effects (whose completions
  // re-enter through here as well).
  function enter(call) {
    if (!alive) return;
    const t0 = perf.enabled ? performance.now() : 0;
    try {
      const changed = call();
      // Stack overflow smashes the host's canary without trapping (see
      // host.rs). Checked before logs, effects and paint so corrupt memory
      // never reaches the page.
      if (!exports.stack_canary_ok()) {
        throw overflowError();
      }
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
      // The host's alloc-time overflow check smashes the canary before it
      // traps (see host.rs), so a dead canary after a throw is the same
      // overflow and gets the same error.
      throw exports.stack_canary_ok() ? err : overflowError();
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

  // A selector-addressed effect that matched nothing is a no-op by design
  // (the app may focus a field only some pages have), so this is
  // information for the developer, not an error: it is how a typo in the
  // selector, or an effect that ran before its element existed, shows up.
  function warnUnmatched(effect, selector) {
    console.warn(`Joy ${effect}: nothing on the page matches "${selector}", so it did nothing.`);
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
      if (!dom.showModal(e.selector)) warnUnmatched('DOM.show_modal', e.selector);
    } else if (e.kind === 'closeModal') {
      if (!dom.closeModal(e.selector)) warnUnmatched('DOM.close_modal', e.selector);
    } else if (e.kind === 'focus') {
      if (!dom.focus(e.selector)) warnUnmatched('DOM.focus', e.selector);
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

  return { start, dispatch, dispatchValue, sendPort, onPort, unmount, perf, hydration: () => hydrateOutcome };
}

const MOUNT_OPTIONS = ['wasm', 'root', 'flags', 'dom', 'setup', 'hydrate'];

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
//   hydrate  claim the server-rendered children of `root` on the first paint
//          instead of clearing them. The server must have rendered the same
//          view the app's init produces (SSR with joy-html); mismatches are
//          repaired and warned about. An empty root hydrates as a plain
//          build, so one loader serves both cases. The returned handle's
//          hydration() reports the outcome ({ claimed, mismatch }, or null
//          when hydrate was off), for tests and monitoring.
export async function mount(options) {
  const { wasm, root, flags, dom = browserDom, setup = null, hydrate = false } = options ?? {};

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
  const rt = makeRuntime(instance.exports, dom, root, hydrate);
  const app = { instance, dispatch: rt.dispatch, dispatchValue: rt.dispatchValue, sendPort: rt.sendPort, onPort: rt.onPort, unmount: rt.unmount, perf: rt.perf, hydration: rt.hydration };
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

// Write a text control's value and keep the caret where the user had it.
// A bare assignment moves the caret to the end. The write happens only on
// drift: the common case, the view taking what the user typed, already
// matches, and an assignment would also end an IME composition. The
// selection offsets shift by the length difference, which is what an edit
// before the caret amounts to: a refused insertion of k characters at p
// left the caret at p+k and goes back to p, a refused backspace goes
// forward again, and a normalized value of the same length keeps its
// caret. Clamped to the new value, and a plain assignment for the input
// types (email, number) that expose no selection.
function writeValue(node, v) {
  const before = node.value;
  if (before === v) return;
  let start = null, end = null, dir = null;
  try { start = node.selectionStart; end = node.selectionEnd; dir = node.selectionDirection; } catch {}
  node.value = v;
  if (typeof before !== 'string' || typeof start !== 'number' || typeof node.setSelectionRange !== 'function') return;
  const shift = before.length - v.length;
  const clamp = (n) => Math.max(0, Math.min(v.length, n - shift));
  try { node.setSelectionRange(clamp(start), clamp(end ?? start), dir ?? undefined); } catch {}
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
    if (k === 'value' && 'value' in node) writeValue(node, v);
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
    return el !== null;
  },
  closeModal: (selector) => {
    const el = document.querySelector(selector);
    if (el && typeof el.close === 'function' && el.open) el.close();
    return el !== null;
  },
  // These three report whether the selector matched at all, so the
  // runtime can warn about the ones that did nothing.
  focus: (selector) => {
    const el = document.querySelector(selector);
    if (!el || typeof el.focus !== 'function') return el !== null;
    el.focus();
    // A text field gets its caret at the end, where typing continues the
    // value (a bare focus() leaves it at the start). Some input types
    // (email, number) refuse setSelectionRange, which is fine to ignore.
    if (typeof el.setSelectionRange === 'function' && typeof el.value === 'string') {
      try { el.setSelectionRange(el.value.length, el.value.length); } catch {}
    }
    return true;
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
  // The hydration probes: what a node is (localName keeps SVG's camelCase,
  // the claim walk compares caselessly), what a text node holds, splitting a
  // text node the serializer merged, and reading an attribute back so
  // matching values skip the write.
  elementTag: (n) => (n.nodeType === 1 ? n.localName : null),
  textValue: (n) => (n.nodeType === 3 ? n.nodeValue : null),
  splitText: (n, offset) => n.splitText(offset),
  getAttr: (n, k) => n.getAttribute(k),
  getProp: (n, k) => n[k],
  setProp: (n, k, v) => { if (k === 'value' && 'value' in n) writeValue(n, v); else n[k] = v; },
  // Every radio sharing the node's name within its form (or the document
  // when it has none): the set the browser toggles together.
  radioGroup: (n) => {
    if (!n.name) return [];
    const scope = n.form ?? n.ownerDocument;
    return Array.from(scope.querySelectorAll('input[type="radio"]')).filter((r) => r.name === n.name);
  },
  // The parser parks a template's children in its content fragment, where
  // the claim walk (which builds them as regular children, like
  // createElement) would leave them duplicated.
  clearParsedTemplate: (n) => { if (n.content) n.content.replaceChildren(); },
};
