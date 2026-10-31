// Joy's hot reloading, for development only. ./joy dev puts this code at the end
// of the runtime.js it serves, so neither a page nor a released runtime.js
// carries any of it. It has three parts:
//
// - Hot reloading a rebuilt bundle (`adopt`). runtime.js's mount hands every app
//   to this module before `init` runs, and the module records the app's
//   session: each message `update` receives, known by a hash of the app's own
//   `Str.inspect` text of it (see host.rs), with the input that produced it.
//   `app.reload` swaps in a rebuilt module without reloading the page: the new
//   module replays the session in a root of its own, getting each message from
//   whichever of its sources still produces exactly that text, and once it has
//   caught up, makes the page's view its own, reusing every element that stays.
//   So the app keeps the state it had reached, even when its model or `update`
//   changed, and the page keeps what it holds in its elements, like the focus.
//   Recording takes a hot build (see host.rs).
//
// - Picking up after a full reload (`saveSessions`, `resume`), when the server
//   changed. The page saves each app's session, reloads, and each app starts
//   from the new markup and replays its session the same way. Here the recorded
//   answers of requests are what was just edited, so none of them is replayed,
//   and a request that writes is never sent twice (see `hold`).
//
// - The dev client, which only runs in a page ./joy dev serves. It listens to
//   the dev server: a rebuilt bundle reloads its apps in place, a restarted
//   server reloads the page, and a failed build shows roc's report over the
//   page until a build succeeds.
//
// The node harnesses import this module to hot reload apps on a fake DOM (see
// tests/check_hot.mjs).

// The ops a message comes in through (see `ops` in runtime.js), by where it
// comes from: a handler in the view (`handler`, the kind of handler it serves),
// an on_visible observer (`observer`), a feature's reply to a call (`answer`)
// or a feature's event for a subscription (`feed`). `inputs` is how many inputs
// an op hands the host after the handler, callback or subscription it is called
// for. What the runtime passes after those is only for this module, where the
// input came from (see `whereFrom`).
const OPS = {
  dispatch: { inputs: 0, handler: 'msg' },
  dispatchValue: { inputs: 1, handler: 'value' },
  dispatchKey: { inputs: 1, handler: 'key' },
  dispatchPointer: { inputs: 1, handler: 'pointer' },
  deliverFile: { inputs: 2, handler: 'file' },
  dispatchVisible: { inputs: 0, observer: true },
  dispatchBytes: { inputs: 1, answer: true },
  dispatchSubBytes: { inputs: 1, feed: true },
};

// The ops that are not a message's way in, which this module handles apart.
const OTHER_OPS = new Set(['endCall', 'drainLog', 'runEffect']);

// The kinds of effect the host queues (see parseEffects in runtime.js).
const CALL = 1;
const SEND = 2;
const SUB_START = 3;
const SUB_STOP = 4;

// The operations that need more than what their kind says. Every other call is
// answered once, every other send is done once it runs, so it never runs again.
const isRequest = (e) => e.kind === CALL && e.op.startsWith('joy/http/');
const isDebounce = (e) => e.kind === CALL && e.op === 'joy/time/debounce';
const isCancel = (e) => e.kind === SEND && e.op === 'joy/time/cancel';
const isDialog = (e) => e.kind === SEND && (e.op === 'joy/dom/show_modal' || e.op === 'joy/dom/close_modal');
const isTitle = (e) => e.kind === SEND && e.op === 'joy/dom/set_title';
const isUrl = (e) => e.kind === SEND && (e.op === 'joy/dom/push_url' || e.op === 'joy/dom/replace_url');

// Inputs that mean nothing to a page that has reloaded: the files it held, and
// the streams and recordings of a Media feature that started over.
const leavesWithPage = (rec) => rec.op === 'deliverFile' || rec.via?.startsWith('joy/media/') === true;

// The host's modes (see hot_mode in host.rs).
const HOT_OFF = 0;
const HOT_RECORD = 1;
const HOT_REPLAY = 2;
const HOT_PROBE = 3;

// The flags of a recorded message (see hot_record in host.rs).
const HOT_AMBIGUOUS = 1;
const HOT_TRUNCATED = 2;

// Each adopted app's current controls (see `instrument`), for `session`.
const controls = new WeakMap();

// Where each adopted app's session is saved across a reload.
const sessionKeys = new WeakMap();

// What each adopted app was mounted with, which says what its bundle is.
const caps = new WeakMap();

// The page's URL when it loaded, where every session on it starts from.
const startUrl = globalThis.location?.href ?? null;

const hot = {
  // The apps this module hot reloads, which the dev client reloads.
  apps: new Set(),
  // What a reload does with a message it cannot replay: 'stop' there or 'skip'
  // it (see `reload` in adopt). It can be changed from the devtools console.
  replay: 'stop',
  // An app's recorded session, to look at from the devtools console: one entry
  // per host entry call that ran `update`, with the op it came in through, its
  // inputs, and the text each message starts with. Null when the app's build
  // does not record.
  session: (app) => controls.get(app)?.().session() ?? null,
  adopt,
  saveSessions,
  appsOf,
};

// How runtime.js's mount finds this module.
globalThis.__JOY_HOT__ = hot;

// Stops a replay at the message that would send a request twice. Thrown from
// `hold`, which ends the instance, and `swap` then replays only what came
// before that message in a fresh one.
class StopBefore {
  constructor(at, request) {
    this.at = at;
    this.request = request;
  }
}

// Take on an app runtime.js just mounted: record its session from here on, and
// give it `app.reload`. `cap` is what mount provides to swap the app's runtime
// for a rebuilt one. Returns what starts the app when a session waits for it
// from before a reload, and null when mount should start it as usual.
function adopt(app, cap) {
  // A runtime.js and a hot.js from different versions of Joy, most likely.
  const unknown = unknownIn(cap.runtime());
  if (unknown) {
    console.error(`Joy: ${unknown} Hot reloading is off for this app, so a rebuild reloads the page.`);
    return null;
  }
  let control = instrument(cap.runtime());
  const recording = control.record();
  controls.set(app, () => control);
  sessionKeys.set(app, sessionKey(cap));
  caps.set(app, cap);
  let queue = Promise.resolve();
  let gone = false;

  // Swap in a rebuilt module, by default from the URL the app was mounted from,
  // without reloading the page, and carry the app's state across. The new
  // module replays this app's session (see catchUp) in a root of its own, and
  // takes over the page only once it has caught up, so a module that fails
  // leaves the running app as it was.
  //
  // `replay` says what to do with a message the replay cannot run, because the
  // new module no longer produces it, it is ambiguous (see `pick`), or replaying
  // it would send a request the old app never sent (see `handover`): 'stop' the
  // replay there, the default, or 'skip' it and carry on.
  //
  // Resolves to a report:
  //
  //   replayed    how many messages replayed
  //   skipped     the text of those left out ('skip')
  //   stopped     the message the replay stopped at ('stop'), with the `reason`
  //               ('gone', 'ambiguous', 'request', 'unsaved' or 'asked', then
  //               with the `request`) and how many messages it left out
  //               (`dropped`)
  //   restarted   whether there was no session to replay (no hot build on
  //               either side), so the app started over
  //   crashed     the error, when replaying crashed the new module, which then
  //               replays up to the message that crashed it: that is how a
  //               fixed crash picks up where the crashed app left off
  //   handedOver  how many requests the old app had in flight now answer the
  //               new one
  //   ignored     the old app's requests in flight that answer nothing now,
  //               being for messages the replay left out
  //   unsent      the requests replaying asked for but did not send ('skip')
  //
  // If `init` crashes, or the module does not compile, this rejects and the
  // running app stays. Reloads run one at a time, each from the app the last
  // one left.
  app.reload = (next = cap.wasm, { replay = 'stop' } = {}) => {
    if (replay !== 'stop' && replay !== 'skip') {
      return Promise.reject(new TypeError(`reload: \`replay\` must be 'stop' or 'skip', not ${JSON.stringify(replay)}`));
    }
    const run = queue.then(() => swap(next, replay, null));
    queue = run.catch(() => {});
    return run;
  };

  const unmount = app.unmount;
  app.unmount = () => {
    gone = true;
    hot.apps.delete(app);
    unmount();
  };

  // `saved` is a session from before a page reload, for the reload's rules (see
  // `hold`). Without it the session is this app's own.
  async function swap(next, replay, saved) {
    if (gone) throw new Error('reload: the app was unmounted');
    const module = await cap.compile(next);
    let limit = Infinity;
    let crashed = null;
    let stoppedForRequest = null;
    const sent = new Map();
    for (;;) {
      const spawned = await cap.spawn(module);
      if (gone) throw new Error('reload: the app was unmounted');
      const session = saved ?? control.session();
      const past = session?.slice(0, limit) ?? null;
      const successor = instrument(spawned.runtime);
      let report;
      try {
        report = await successor.catchUp(cap.flags, past, replay, saved ? sent : null);
      } catch (err) {
        if (err instanceof StopBefore) {
          stoppedForRequest = {
            text: past[err.at].msgs[0]?.text ?? '',
            reason: 'request',
            request: err.request,
            dropped: session.slice(err.at).reduce((n, entry) => n + entry.msgs.length, 0),
          };
          limit = err.at;
          continue;
        }
        // A trapped instance is unusable, so the retry starts a fresh one.
        // Replay is deterministic, so the shorter session cannot crash.
        if (err.replayAt === undefined || crashed) throw err;
        crashed = err;
        limit = err.replayAt;
        continue;
      }
      const plan = handover(control.inFlight(), successor.leftovers(), report.restarted);
      // Stopping at a request the old app never sent means replaying only what
      // came before the message that asked for it. Which messages those are is
      // only known once the whole replay has run, since a recorded answer may
      // come for a request at any later point, so the replay runs again, as for
      // a crash. It cannot ask for such a request again: the earliest one was
      // cut off, and what comes before is unchanged.
      if (replay === 'stop' && plan.unsent.length > 0 && !stoppedForRequest) {
        const first = plan.unsent.reduce((a, b) => (b.from.entry < a.from.entry ? b : a));
        const at = first.from.entry;
        stoppedForRequest = {
          text: past[at].msgs[first.from.msg].text,
          reason: 'request',
          request: successor.describe(first),
          dropped: session.slice(at).reduce((n, entry) => n + entry.msgs.length, 0),
        };
        limit = at;
        continue;
      }
      successor.goLive(cap.root, plan, control);
      cap.replace(spawned);
      control = successor;
      return {
        ...report,
        reloaded: saved !== null,
        stopped: stoppedForRequest ?? report.stopped,
        crashed,
        handedOver: plan.pairs.filter(({ next: asked }) => isRequest(asked)).length,
        ignored: plan.ignored.map(successor.describe),
        unsent: plan.unsent.map(successor.describe),
      };
    }
  }

  hot.apps.add(app);

  // The session this app had before the page reloaded, when there is one. The
  // first instance claims the page's markup with everything it asks for held
  // back, and the replay then runs in a fresh one, which takes over from it, as
  // a replay can only be cut short by starting over.
  const waiting = recording ? takeSession(sessionKeys.get(app)) : null;
  if (!waiting) return null;
  return async () => {
    const session = await waiting;
    if (!session || session.length === 0) {
      cap.runtime().hooks.start(cap.flags);
      return;
    }
    control.holdBack();
    cap.runtime().hooks.start(cap.flags);
    const run = swap(cap.wasm, hot.replay, session);
    queue = run.catch(() => {});
    try {
      report(await run);
    } catch (err) {
      console.error(err);
      overlay.show(`The app crashed while picking up where it was, so it started over.\n\n${describe(err)}`);
      control.letGo();
    }
  };
}

// Decide what becomes of the one-shot calls in flight when a rebuilt app takes
// over: those the old app started and has not had back (`waiting`, oldest
// first), and those the new one asked for while replaying the session and that
// no recorded answer answered (`leftovers`, in the order asked).
//
// A call of each that is the same call (`sameCall`) is the same thing still
// under way, paired oldest first: the old app's carries on, and its answer goes
// to the new app (see goLive). So a request is not sent again, a timer keeps the
// time it had left, and a digest is not worked out again. An old one without a
// partner was asked for by a message the replay left out, or that the new code
// no longer has ask for it, so nothing waits for it any more: a request of those
// is `ignored`. A new one without a partner is new: the new code asks for it
// where the old did not. A timer or a digest is the app's own business and runs,
// and so does a request the new `init` asks for, as on a fresh page load. But a
// request asked for by a replayed message, which the old app never sent, is
// `unsent`: sending it would do now, on the old session's behalf, what nobody
// asked for, while not sending it leaves the app waiting for an answer that
// never comes. So it is up to the replay policy (see `swap`). A request a page
// reload sent again (`pending`) is under way already. A restarted app replayed
// nothing, and takes over nothing.
function handover(waiting, leftovers, restarted) {
  const free = [...leftovers];
  const pairs = [];
  const ignored = [];
  for (const old of waiting) {
    const at = restarted ? -1 : free.findIndex((e) => sameCall(old, e));
    if (at >= 0) pairs.push({ old, next: free.splice(at, 1)[0] });
    else if (isRequest(old)) ignored.push(old);
  }
  const unsent = free.filter((e) => isRequest(e) && e.from !== null && !e.pending);
  const fresh = free.filter((e) => !unsent.includes(e));
  return { pairs, ignored, unsent, fresh };
}

// Whether two calls are the same call: one operation with the same arguments.
// So two requests are the same request when their method, URL, headers, body
// (or file slice) and timeout are: two in flight at once that differ only in a
// header never answer each other, and a request an edit changed in any way is
// a new one, since the old one's answer may not be what the new code asks for
// (a JSON answer to a request that now accepts CSV).
const sameCall = (a, b) => a.op === b.op && sameBytes(a.args, b.args);

const sameBytes = (a, b) => a.length === b.length && a.every((byte, i) => byte === b[i]);

// What of a runtime this module would have to guess about, as it does not
// describe it: an op (see OPS). Null when there is nothing.
function unknownIn(rt) {
  const op = Object.keys(rt.hooks.ops).find((name) => !OPS[name] && !OTHER_OPS.has(name));
  return op ? `the runtime has an op ${op}, which www/hot.js does not describe in OPS.` : null;
}

// Wire a runtime up for hot reloading, through the hooks runtime.js gives this
// module: wrap its ops, so that its session can be recorded and another's
// replayed into it. Returns what drives that.
function instrument(rt) {
  const { exports, dom, ops, str, hears, reader } = rt.hooks;
  // The runtime's own ops, which the wrappers below and a replay call.
  const plain = { ...ops };

  // The session record, one entry per host entry call that ran `update`: the op
  // it came in through, the inputs that op was given, where they came from (see
  // `whereFrom`), the requests it asked for (`asked`) and each message (see
  // `readMessage`). Null when not recording.
  let history = null;

  // The entry the running dispatch records into, which `drain` completes.
  let current = null;

  // The entry the effects running now belong to, null for those of `init`.
  let lastEntry = null;

  // The calls this app started, or took over, and has not had back yet, oldest
  // first: what a successor takes over (see `handover`).
  let inFlight = [];

  // Answers this app passes on once retired, by callback: those of the calls in
  // flight its successor took over (see goLive), which is also how they reach a
  // successor of the successor.
  const forwards = new Map();

  // The last dialog effect for each selector, run or, while replaying, held:
  // the state this app leaves its dialogs in.
  const dialogs = new Map();

  // While this runtime replays another's session (see catchUp), the effects its
  // replayed `update`s ask for are held here instead of run: the old app already
  // ran them. What is held when the replay ends is settled by `handover`, along
  // with the subscriptions the replay ended with.
  let replaying = null;

  // Which replayed message is running, { entry, msg } into the session, so a
  // held effect knows what asked for it. Null while `init` runs.
  let replayingAt = null;

  // What catchUp kept of the old app's session, which this app records on from
  // once live.
  let caughtUp = [];

  // Set while goLive makes the page's view this app's. An event that fires
  // meanwhile, like a blur when the focused element is removed, is an echo,
  // dropped as those the runtime's own paints fire are.
  let adopting = false;

  // --- Reading effects ---

  // A request's method, URL and headers, which is what makes it the same request
  // as far as a page reload is concerned.
  function requestOf(e) {
    const args = reader(e.args);
    const method = args.str();
    const url = args.str();
    const headers = [];
    for (let n = args.u32(); n > 0; n--) headers.push([args.str(), args.str()]);
    return { method, url, headers };
  }
  const requestKey = (e) => {
    const { method, url, headers } = requestOf(e);
    return JSON.stringify([method, url, headers]);
  };
  const describe = (e) => {
    const { method, url } = requestOf(e);
    return `${method} ${url}`;
  };
  const firstStr = (e) => reader(e.args).str();

  // --- Recording ---

  // Every op that brings a message in, recording what it brings when recording.
  // An answer to a call a successor took over goes there.
  for (const [name, op] of Object.entries(OPS)) {
    ops[name] = (source, ...args) => {
      const inputs = args.slice(0, op.inputs);
      if (op.answer) {
        settle(source);
        const forward = forwards.get(source);
        if (forward) {
          forwards.delete(source);
          forward(inputs[0]);
          return;
        }
      }
      if (adopting && (op.handler || op.observer)) return;
      current = history && { op: name, inputs, ...whereFrom(op, args[op.inputs]), msgs: [] };
      try {
        plain[name](source, ...inputs);
      } finally {
        current = null;
      }
    };
  }
  // A call that ended without an answer, which a successor may be waiting on.
  ops.endCall = (cb) => {
    settle(cb);
    const forward = forwards.get(cb);
    if (forward) {
      forwards.delete(cb);
      forward(null);
      return;
    }
    plain.endCall(cb);
  };
  ops.drainLog = drain;
  // Tracked before it runs, since some complete at once.
  ops.runEffect = (e) => {
    if (replaying) {
      hold(e);
    } else {
      track(e);
      plain.runEffect(e);
    }
  };

  // Where an input came from, as far as a replay needs it (see `sourcesFor`). For
  // a handler or an observer, its node's position, which a replay offers first,
  // and for a handler the event it took. The node itself stays until `drain`
  // knows whether the message needs its element's signature. For a reply or an
  // event, the operation and arguments of the effect behind it.
  function whereFrom(op, context) {
    if (op.observer) return at(context);
    if (op.handler) return context?.currentTarget ? { ...at(context.currentTarget), event: context.type } : {};
    if (context === undefined) return {};
    return { via: context.op, args: context.args, ...(isRequest(context) ? { request: requestKey(context) } : {}) };
  }
  const at = (node) => ({ at: rt.hooks.nodes().indexOf(node), node });

  // An effect this app runs: a call it now waits for, and the state of a dialog.
  // A debounce re-armed or cancelled ends the call waiting under its key through
  // the feature itself, which comes back as `endCall`.
  function track(e) {
    if (e.kind === CALL) {
      inFlight.push(e);
      if (isRequest(e) && lastEntry) (lastEntry.asked ??= []).push(requestKey(e));
    } else if (isDialog(e)) {
      dialogs.set(firstStr(e), e);
    }
  }

  // An answer, which settles the call whose callback it answers.
  function settle(cb) {
    const found = inFlight.findIndex((e) => e.cb === cb);
    if (found >= 0) inFlight.splice(found, 1);
  }

  // The runtime's log drain, which also collects each message the running
  // dispatch ran: a recording hot build queues them at level 2 (see hot_record in
  // host.rs). The runtime drains after the call and before the paint, so this is
  // where an entry is complete, while the view is still the one its event
  // happened in. A replay prints nothing: the old app already logged all of it
  // once.
  function drain() {
    const n = exports.log_len();
    if (n > 0) {
      const w = new Uint32Array(exports.memory.buffer, exports.log_ptr(), n);
      for (let i = 0; i + 2 < n; i += 3) {
        const level = w[i + 2];
        if (level === 2) current?.msgs.push(readMessage(w[i], w[i + 1]));
        else if (replaying && !replaying.loud) continue;
        else if (level === 1) console.debug(str(w[i], w[i + 1]));
        else console.log(str(w[i], w[i + 1]));
      }
      exports.log_clear();
    }
    const entry = current;
    current = null;
    lastEntry = entry && entry.msgs.length > 0 ? entry : null;
    if (!entry) return;
    // Only an ambiguous message's source is told apart by its element (see
    // `pick`), and reading an element's text walks its whole subtree. Then the
    // node goes, so the record never holds on to the view.
    if (entry.node) {
      if (entry.msgs.some((msg) => msg.ambiguous)) Object.assign(entry, signatureOf(entry.node));
      delete entry.node;
    }
    // Recorded before the effects run, since one can re-enter at once (a port
    // handler that answers through app.sendPort) and its entry belongs after this
    // one.
    if (entry.msgs.length > 0) history?.push(entry);
  }

  // A recorded message (see hot_record in host.rs): the hash it is known by,
  // whether its text is ambiguous, and how its text starts, for showing.
  function readMessage(ptr, len) {
    const view = new DataView(exports.memory.buffer, ptr, len);
    const flags = view.getUint8(16);
    return {
      hash: [view.getUint32(0, true), view.getUint32(4, true), view.getUint32(8, true), view.getUint32(12, true)],
      ambiguous: (flags & HOT_AMBIGUOUS) !== 0,
      text: str(ptr + 17, len - 17) + (flags & HOT_TRUNCATED ? '…' : ''),
    };
  }

  // What an element in the view is recognised by when its handler's message
  // cannot tell it apart from another (see `pick`): its id and its text.
  const signatureOf = (node) => ({ id: dom.getAttr(node, 'id'), text: node.textContent });

  // Record the session from here on, continuing `past` when this app replayed
  // one. Returns whether this is a hot build, the only kind that can.
  function record(past = []) {
    if (exports.hot_mode?.(HOT_RECORD) !== 1) return false;
    history = past;
    return true;
  }

  // Hold back everything this app asks for and record nothing, while it stands
  // on the page for the app that replays a saved session (see `resume`).
  function holdBack() {
    exports.hot_mode?.(HOT_OFF);
    history = null;
    replaying = { oneShots: [], subs: new Map(), loud: true };
  }

  // Run what `holdBack` held back and record from here on, as a page with no
  // session to pick up does.
  function letGo() {
    const held = replaying;
    replaying = null;
    record();
    for (const e of held.oneShots) ops.runEffect(e);
    for (const e of held.subs.values()) ops.runEffect(e);
  }

  // --- Replaying ---

  // Hold an effect a replayed `update` asked for (see `replaying`), noting which
  // message asked. A call's callback stays held until a replayed answer matches
  // it, or a keyed effect ends it, which releases it exactly as running them
  // would. A command already ran, in the old app, and only the last title and
  // URL matter to a page that has reloaded, as the dialogs do to any page.
  //
  // After a page reload the recorded answers of requests are what was just
  // edited, so each request `again` decides (see `askAgain`) is sent.
  function hold(e) {
    const held = replaying;
    e.from = replayingAt;
    if (e.kind === SUB_START) {
      held.subs.set(e.id, e);
    } else if (e.kind === SUB_STOP) {
      held.subs.delete(e.id);
    } else if (e.kind === CALL) {
      if (isDebounce(e)) dropKeyed(held, firstStr(e));
      if (isRequest(e) && held.again) askAgain(held, e);
      held.oneShots.push(e);
    } else if (isCancel(e)) {
      dropKeyed(held, firstStr(e));
    } else if (isDialog(e)) {
      dialogs.set(firstStr(e), e);
    } else if (isTitle(e)) {
      held.title = e;
    } else if (isUrl(e)) {
      held.url = firstStr(e);
    }
  }

  function dropKeyed(held, key) {
    const found = held.oneShots.findIndex((waiting) => isDebounce(waiting) && firstStr(waiting) === key);
    if (found >= 0) exports.drop_call_cb(held.oneShots.splice(found, 1)[0].cb);
  }

  // A request a replay asks for after a page reload:
  //
  // - One `init` asks for is sent, as on any page load.
  // - A GET or HEAD the recorded message asked for too, by method, URL and
  //   headers, is sent, and the replay goes on with the new server's answer.
  // - Any other GET or HEAD is sent, and the replay stops after that message.
  // - Any other request stops the replay before that message, so a POST is never
  //   sent twice.
  //
  // A replay that stops starts over (see StopBefore), so what it sent is kept in
  // `again.sent` and the same request is not sent a second time on the way back.
  function askAgain(held, e) {
    const { method } = requestOf(e);
    const safe = method === 'GET' || method === 'HEAD';
    const key = requestKey(e);
    if (e.from !== null) {
      if (!safe) throw new StopBefore(e.from.entry, describe(e));
      if (!held.past[e.from.entry].asked?.includes(key)) held.stopAfter = describe(e);
    }
    const tries = held.again.sent.get(key) ?? [];
    held.again.sent.set(key, tries);
    const index = held.again.used.get(key) ?? 0;
    held.again.used.set(key, index + 1);
    if (index >= tries.length) tries.push(rt.hooks.perform(e));
    e.pending = tries[index];
  }

  // The nodes of the view, the one at `position` first.
  function fromPosition(position) {
    const nodes = rt.hooks.nodes();
    return position >= 0 && position < nodes.length
      ? [nodes[position], ...nodes.slice(0, position), ...nodes.slice(position + 1)]
      : nodes;
  }

  // The effects `rec` could have come through, those with its arguments first.
  const likeliest = (effects, rec) => {
    const same = effects.filter((e) => e.op === rec.via);
    const exact = (e) => (rec.args && sameBytes(e.args, rec.args) ? 0 : 1);
    return same.map((e, i) => [exact(e), i, e]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map(([, , e]) => e);
  };

  // Whether a subscription would hear an event recorded for one of its operation:
  // a port by its name, and a key by the event and the key filter, which live in
  // the arguments and run in the feature. An edited interval hears its ticks.
  function stillHears(e, rec) {
    if (e.op === 'joy/port/listen') return sameBytes(e.args, rec.args);
    if (e.op !== 'joy/keyboard/keys') return true;
    const args = reader(e.args);
    const event = args.str();
    const keys = [];
    for (let n = args.u32(); n > 0; n--) keys.push(args.str());
    return event === reader(rec.args).str() && hears(keys, reader(rec.inputs[0]).str());
  }

  // Every source in this app that could produce a message the recorded entry's
  // op brought in, each as a `run` that hands the source the entry's inputs
  // through that op. Likeliest first: the handler on the node where the event
  // happened, and held effects in the order they were asked for. A handler in
  // the view carries its `node`, and `used` forgets a one-shot callback that
  // matched, which the host has released.
  function sourcesFor(rec) {
    const op = OPS[rec.op];
    const call = (source) => () => plain[rec.op](source, ...rec.inputs);
    const sources = [];
    if (op.handler) {
      for (const node of fromPosition(rec.at)) {
        const handlers = rt.hooks.handlers(node);
        // A page's own app.dispatch names no event, so any handler may be the one.
        const named = rec.event === undefined ? [...(handlers?.values() ?? [])] : [handlers?.get(rec.event)];
        for (const d of named) {
          // A key handler hears the keys its filter lets through, as in the
          // runtime's listener.
          if (d?.kind !== op.handler || (d.kind === 'key' && !hears(d.keys, rec.inputs[0].key))) continue;
          sources.push({ run: call(d.id), node });
        }
      }
    } else if (op.observer) {
      for (const node of fromPosition(rec.at)) {
        const v = rt.hooks.visibility(node);
        if (v) sources.push({ run: call(v.id), node });
      }
    } else if (op.answer) {
      const held = replaying.oneShots;
      for (const e of likeliest(held, rec)) {
        sources.push({ run: call(e.cb), used: () => held.splice(held.indexOf(e), 1) });
      }
    } else {
      for (const e of likeliest([...replaying.subs.values()], rec)) {
        if (stillHears(e, rec)) sources.push({ run: call(e.id) });
      }
    }
    return sources;
  }

  // Replay one recorded message: offer the recorded input to each source that
  // could produce it until the host reports one did (see hot_expect), which has
  // then run `update` with it. Returns 'ran', 'gone' when no source produces it
  // any more, or 'ambiguous' when its text is ambiguous and `pick` cannot tell
  // which source produced it.
  function offer(rec, msg) {
    let sources = sourcesFor(rec);
    if (msg.ambiguous) {
      const source = pick(rec, msg, sources);
      if (!source) return 'ambiguous';
      sources = [source];
    }
    exports.hot_expect(...msg.hash);
    for (const source of sources) {
      source.run();
      if (exports.hot_matched()) {
        source.used?.();
        return 'ran';
      }
    }
    return 'gone';
  }

  // The source of an ambiguous message, which the first source to match may not
  // be: a function or an opaque value prints without its contents, so two
  // different messages can read the same. Every source is probed, which runs
  // nothing (see hot_mode), and one is used only if it is the only match, or,
  // when several match, the only match on an element with the recorded id and
  // text. Null otherwise.
  function pick(rec, msg, sources) {
    exports.hot_mode(HOT_PROBE);
    exports.hot_expect(...msg.hash);
    const matches = sources.filter((source) => {
      const before = exports.hot_matched();
      source.run();
      return exports.hot_matched() > before;
    });
    exports.hot_mode(HOT_REPLAY);
    if (matches.length === 1) return matches[0];
    const same = matches.filter((source) => {
      if (!source.node) return false;
      const { id, text } = signatureOf(source.node);
      return id === rec.id && text === rec.text;
    });
    return matches.length > 1 && same.length === 1 ? same[0] : null;
  }

  // Replay the answer to a request a page reload sent again: whatever the new
  // server said goes in, recording the message it makes in place of the old one,
  // whose text no longer has to match. Returns the new entry, or null when the
  // replay never got to ask for that request.
  async function answerAgain(rec) {
    const held = replaying.oneShots;
    const e = held.find((waiting) => waiting.pending && requestKey(waiting) === rec.request);
    if (!e) return null;
    held.splice(held.indexOf(e), 1);
    const reply = await e.pending;
    if (reply === undefined || typeof reply === 'symbol') {
      plain.endCall(e.cb);
      return { ...rec, msgs: [] };
    }
    const entry = { op: rec.op, inputs: [reply], via: rec.via, args: rec.args, request: rec.request, asked: rec.asked, msgs: [] };
    exports.hot_mode(HOT_RECORD);
    current = entry;
    try {
      plain.dispatchBytes(e.cb, reply);
    } finally {
      current = null;
      exports.hot_mode(HOT_REPLAY);
    }
    return entry;
  }

  // Start this runtime as the successor of a running app, in its own root. With
  // the old app's session record and a hot build to replay it in, every recorded
  // message is replayed, each from whichever source in this app still produces
  // exactly that message. A message the replay cannot run, because nothing
  // produces it any more (its button is gone, its request is no longer sent) or
  // because it is ambiguous and its source cannot be told (see `pick`), is
  // handled by `policy`:
  //
  //   'stop'  end the replay there, so the app is left in a state it really had,
  //           the one just before that message
  //   'skip'  leave the message out and carry on, which keeps more of the
  //           session, in a state the app may never have had exactly
  //
  // Neither ever runs a message other than the recorded one. `sent` holds the
  // requests already sent when the session comes from before a page reload, and
  // is null otherwise. Throws when the app crashes, with `replayAt` set when a
  // replayed message did it, or a StopBefore.
  async function catchUp(flags, past, policy, sent) {
    replaying = {
      oneShots: [],
      subs: new Map(),
      past,
      again: sent && { sent, used: new Map() },
      stopAfter: null,
      title: null,
      url: null,
    };
    replayingAt = null;
    const replay = past != null && exports.hot_mode?.(HOT_REPLAY) === 1;
    rt.hooks.start(flags);
    const kept = [];
    const skipped = [];
    let replayed = 0;
    let stopped = null;
    for (let i = 0; replay && i < past.length && !stopped; i++) {
      const rec = past[i];
      const left = () => past.slice(i).reduce((n, entry) => n + entry.msgs.length, 0);
      if (sent && rec.unsaved) {
        stopped = { text: rec.msgs[0]?.text ?? '', reason: 'unsaved', dropped: left() };
        break;
      }
      if (sent && rec.request) {
        replayingAt = { entry: i, msg: 0 };
        let entry;
        try {
          entry = await answerAgain(rec);
        } catch (cause) {
          if (cause instanceof StopBefore) throw cause;
          throw Object.assign(new Error(`Joy: the app crashed replaying ${rec.msgs[0]?.text}`, { cause }), { replayAt: i });
        }
        if (!entry) {
          stopped = { text: rec.msgs[0]?.text ?? '', reason: 'gone', dropped: left() };
          break;
        }
        kept.push(entry);
        replayed += entry.msgs.length;
      } else {
        const msgs = [];
        for (let j = 0; j < rec.msgs.length; j++) {
          const msg = rec.msgs[j];
          replayingAt = { entry: i, msg: j };
          let outcome;
          try {
            outcome = offer(rec, msg);
          } catch (cause) {
            if (cause instanceof StopBefore) throw cause;
            throw Object.assign(new Error(`Joy: the rebuilt app crashed replaying ${msg.text}`, { cause }), { replayAt: i });
          }
          if (outcome !== 'ran' && policy === 'stop') {
            // This message and every one after it are left out.
            const later = past.slice(i + 1).reduce((n, entry) => n + entry.msgs.length, 0);
            stopped = { text: msg.text, reason: outcome, dropped: rec.msgs.length - j + later };
            break;
          }
          (outcome === 'ran' ? msgs : skipped).push(outcome === 'ran' ? msg : msg.text);
        }
        if (msgs.length > 0) kept.push({ ...rec, msgs });
        replayed += msgs.length;
      }
      if (!stopped && replaying.stopAfter) {
        const later = past.slice(i + 1).reduce((n, entry) => n + entry.msgs.length, 0);
        stopped = { text: rec.msgs[0]?.text ?? '', reason: 'asked', request: replaying.stopAfter, dropped: later + 1 };
      }
    }
    replayingAt = null;
    caughtUp = kept;
    return { replayed, skipped, stopped, restarted: !replay };
  }

  // --- Taking over ---

  // Stop this app for its successor (see goLive): the runtime runs nothing from
  // here on, and this only passes on answers its successor took over. Its
  // handlers and visibility observers come off its view, whose elements the
  // successor reuses. Returns the observers it had, by element.
  function retire() {
    rt.hooks.retire();
    const watched = new Map();
    const strip = (node) => {
      for (const name of rt.hooks.handlers(node)?.keys() ?? []) {
        for (const listener of rt.hooks.listeners) node.removeEventListener?.(name, listener);
      }
      for (const listener of rt.hooks.listeners) node.removeEventListener?.('compositionend', listener);
      const v = rt.hooks.visibility(node);
      if (v) {
        v.disconnect();
        watched.set(node, v);
      }
      for (const child of dom.childrenOf(node)) strip(child);
    };
    for (const child of dom.childrenOf(rt.hooks.root())) strip(child);
    return watched;
  }

  // Put a caught-up runtime on the page in place of the app it succeeds,
  // `predecessor`, which retires: make the view under `target` this app's (see
  // `morph`), record from here on, and settle what the replay held back as `plan`
  // says (see `handover`). A call this app takes over keeps going in the old app,
  // which passes its answer on to this one (see `forwards`).
  function goLive(target, plan, predecessor) {
    const watched = predecessor.retire();
    const kept = new Map();
    adopting = true;
    try {
      morph(target, rt.hooks.root(), watched, kept);
    } finally {
      adopting = false;
    }
    rt.hooks.setRoot(target, kept);
    const held = replaying;
    replaying = null;
    if (!record(caughtUp)) exports.hot_mode?.(HOT_OFF);
    for (const { old, next } of plan.pairs) {
      inFlight.push(next);
      predecessor.forward(old.cb, (reply) => {
        if (reply === null) ops.endCall(next.cb);
        else ops.dispatchBytes(next.cb, reply, next);
      });
    }
    for (const e of plan.fresh) {
      if (e.pending) {
        inFlight.push(e);
        e.pending.then((reply) => {
          if (typeof reply === 'symbol') ops.endCall(e.cb);
          else ops.dispatchBytes(e.cb, reply, e);
        });
      } else {
        ops.runEffect(e);
      }
    }
    for (const e of held.subs.values()) ops.runEffect(e);
    // The dialogs end as the replay left them: one the old app had a say on and
    // the replay never had ends closed. One the replay left as the old app did
    // is the page's to keep, as the user may have closed it with Escape since.
    const before = predecessor.dialogs();
    for (const [selector, e] of before) {
      if (!dialogs.has(selector)) dialogs.set(selector, { ...e, op: 'joy/dom/close_modal' });
    }
    for (const [selector, e] of dialogs) {
      if (before.get(selector)?.op !== e.op) plain.runEffect(e);
    }
    if (held.again) {
      if (held.title) plain.runEffect(held.title);
      if (held.url !== null) dom.replaceUrl(held.url);
    }
  }

  // Make the page's view, the children of `live`, into this app's own, the
  // children of `fresh`, keeping every node of the page's that still fits (see
  // `fitAt`): patched to match, an element keeps what the page keeps in it, the
  // focus, a scroll position, an open <details>, a playing video, and this app
  // takes over its handlers and observer (see `keep`). Where none fits, this
  // app's own node goes in. Nodes pair up in order, as the host's own diff pairs
  // them, except that an element that no longer fits is passed over for a later
  // one that does, so that a new element does not shift every element after it
  // onto the wrong one. `watched` has the predecessor's visibility observers, and
  // `kept` collects which node of the page stands for which of this app's.
  function morph(live, fresh, watched, kept) {
    const old = [...dom.childrenOf(live)];
    let next = 0;
    for (const node of [...dom.childrenOf(fresh)]) {
      const found = fitAt(old, next, node);
      if (found < 0) {
        dom.insertBefore(live, node, old[next] ?? null);
        continue;
      }
      for (; next < found; next++) dom.remove(old[next]);
      next++;
      kept.set(node, old[found]);
      keep(old[found], node, watched, kept);
    }
    for (; next < old.length; next++) dom.remove(old[next]);
  }

  // Where in `old`, from `next` on, the first node is that `node` fits: an element
  // of the same tag and id, or for text, the next node when it is text. -1 when
  // there is none.
  function fitAt(old, next, node) {
    const tag = dom.elementTag(node);
    if (tag === null) return old[next] !== undefined && dom.elementTag(old[next]) === null ? next : -1;
    const id = dom.getAttr(node, 'id');
    for (let i = next; i < old.length; i++) {
      if (dom.elementTag(old[i]) === tag && dom.getAttr(old[i], 'id') === id) return i;
    }
    return -1;
  }

  // Make `liveNode`, of the page's view, into `freshNode`, of this app's own, whose
  // place it takes: the same text, or the same attributes, with this app's
  // handlers and observer, and children made the same way. An element's `open`
  // stays as it is unless this app's view sets it, as it is the page's to keep: a
  // user opens a <details>, and showModal a <dialog> (whose state goLive settles).
  // An observer that is the same as the predecessor's had (see setVisibility in
  // runtime.js) does not tell this app the element is in view, since the
  // predecessor was told.
  function keep(liveNode, freshNode, watched, kept) {
    if (dom.elementTag(liveNode) === null) {
      const text = dom.textValue(freshNode);
      if (dom.textValue(liveNode) !== text) dom.setText(liveNode, text);
      return;
    }
    const names = dom.attrNames(freshNode);
    for (const name of dom.attrNames(liveNode)) {
      if (!names.includes(name) && name !== 'open') dom.removeAttr(liveNode, name, true);
    }
    for (const name of names) {
      const value = dom.getAttr(freshNode, name, true);
      if (dom.getAttr(liveNode, name, true) !== value) dom.setAttr(liveNode, name, value);
    }
    const was = watched.get(liveNode);
    const now = rt.hooks.visibility(freshNode);
    rt.hooks.adopt(freshNode, liveNode, Boolean(was && now && was.margin === now.margin && was.key === now.key));
    morph(liveNode, freshNode, watched, kept);
    rt.hooks.pin(liveNode);
  }

  return {
    record,
    holdBack,
    letGo,
    describe,
    session: () => history,
    inFlight: () => inFlight,
    leftovers: () => replaying.oneShots,
    dialogs: () => dialogs,
    forward: (cb, deliver) => forwards.set(cb, deliver),
    catchUp,
    retire,
    goLive,
  };
}

// --- Sessions across a page reload ---
// Saved in sessionStorage, compressed with the browser's own CompressionStream,
// and without the bodies of HTTP answers, which this replay never uses. A session
// is mostly the same few messages over and over, so it compresses well. A session
// that still does not fit is not saved, the console says so, and the page reloads
// without it.

// A session finds its root by the bundle's id and its place among the roots with
// that id, or for an app mounted by hand, by the module's URL and how many apps
// are on it already.
function sessionKey(cap) {
  const bundle = cap.root.dataset?.joyBundle;
  if (bundle !== undefined && globalThis.document) {
    const place = [...document.querySelectorAll(`[data-joy-bundle="${CSS.escape(bundle)}"]`)].indexOf(cap.root);
    return `joy/session/${bundle}/${place}`;
  }
  const base = `joy/session/${typeof cap.wasm === 'string' ? cap.wasm : 'app'}/`;
  const place = [...hot.apps].filter((app) => sessionKeys.get(app).startsWith(base)).length;
  return `${base}${place}`;
}

// The apps a rebuild of the bundle `id` reaches. An app mounted by hand has no
// id, so its module's URL tells, and one mounted from bytes could be any bundle.
function appsOf(id) {
  return [...hot.apps].filter((app) => {
    const { root, wasm } = caps.get(app);
    const bundle = root.dataset?.joyBundle;
    if (bundle !== undefined) return bundle === id;
    return typeof wasm !== 'string' || wasm.split(/[?#]/)[0].endsWith(`${id}/app.wasm`);
  });
}

function toBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

function fromBase64(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// An entry as JSON can hold it: without what a reloaded page has no use for, and
// with bytes as text.
function savable(rec) {
  const entry = { ...rec, inputs: rec.request || leavesWithPage(rec) ? [] : rec.inputs };
  if (leavesWithPage(rec)) entry.unsaved = true;
  return entry;
}

const encodeBytes = (_, value) => (value instanceof Uint8Array ? { joyBytes: toBase64(value) } : value);
const decodeBytes = (_, value) => (value?.joyBytes === undefined ? value : fromBase64(value.joyBytes));

// Save the session of every app on the page, for the page to pick up after it
// reloads.
async function saveSessions() {
  for (const app of hot.apps) {
    const session = hot.session(app);
    if (!session || session.length === 0) continue;
    try {
      const text = JSON.stringify(session.map(savable), encodeBytes);
      const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
      const zipped = new Uint8Array(await new Response(stream).arrayBuffer());
      sessionStorage.setItem(sessionKeys.get(app), toBase64(zipped));
    } catch (err) {
      console.warn(`Joy: this page's session did not fit in sessionStorage, so it starts over after the reload. ${err}`);
    }
  }
}

// The session saved under `key`, read once, or null when there is none.
function takeSession(key) {
  const stored = globalThis.sessionStorage?.getItem(key);
  if (!stored) return null;
  sessionStorage.removeItem(key);
  return (async () => {
    try {
      const stream = new Blob([fromBase64(stored)]).stream().pipeThrough(new DecompressionStream('gzip'));
      return JSON.parse(await new Response(stream).text(), decodeBytes);
    } catch (err) {
      console.warn(`Joy: this page's saved session could not be read, so it starts over. ${err}`);
      return null;
    }
  })();
}

// --- The dev client ---
// Only in a page: it listens to the dev server's event stream, whose port ./joy
// dev defines in front of this code. When a bundle is rebuilt it reloads that
// bundle's apps in place, and when a build fails it shows roc's report over the
// page until a build succeeds. After a server change, or a change of a file the
// page loaded, it saves the sessions and reloads.
if (globalThis.document && globalThis.EventSource && typeof JOY_DEV_PORT !== 'undefined') connect(JOY_DEV_PORT);

function connect(port) {
  // Reloads run one at a time, in the order the builds landed.
  let queue = Promise.resolve();
  let build = null;
  let leaving = false;

  const events = new EventSource(`${location.protocol}//${location.hostname}:${port}/.joy/events`);

  // A reconnect, to a dev server that restarted or after a rebuild this page
  // never heard of.
  events.addEventListener('hello', (e) => {
    if (build !== null && build !== e.data) leave();
    build = e.data;
  });

  events.addEventListener('reload', (e) => {
    queue = queue.then(() => reloadBundle(e.data));
  });

  events.addEventListener('server', () => leave());

  events.addEventListener('failed', (e) => {
    const [name, ...log] = e.data.split('\n');
    console.error(`Joy: ${name} failed to build\n${log.join('\n')}`);
    overlay.show(log.join('\n'));
  });
  events.addEventListener('fixed', () => overlay.hide());

  events.addEventListener('asset', (e) => {
    const file = `/${e.data}`;
    const sheets = [...document.querySelectorAll('link[rel="stylesheet"]')].filter((link) => new URL(link.href).pathname.endsWith(file));
    if (sheets.length > 0) {
      for (const link of sheets) {
        const url = new URL(link.href);
        url.searchParams.set('joy', String(Date.now()));
        link.href = url.href;
      }
    } else if (performance.getEntriesByType('resource').some((entry) => new URL(entry.name).pathname.endsWith(file))) {
      leave();
    }
  });

  // The page takes the new files only if the browser asks for them again.
  fetch(import.meta.url, { method: 'HEAD', cache: 'no-store' }).then((answer) => {
    if (!/no-cache|no-store|max-age=0/.test(answer.headers.get('cache-control') ?? '')) {
      console.warn('Joy: whatever serves this page does not ask the browser to revalidate its files, so a reload can show an old copy. Add Cache-Control: no-cache in development.');
    }
  }, () => {});

  async function reloadBundle(id) {
    const apps = appsOf(id);
    // No app means the page never got one going, most likely because it opened
    // while the build was broken, or that it does not hold this bundle.
    if (hot.apps.size === 0) return leave();
    for (const app of apps) {
      // A build without hot reloading (./joy dev --no-hot) can only start over.
      if (hot.session(app) === null) return leave();
      try {
        report(await app.reload(undefined, { replay: hot.replay }));
      } catch (err) {
        console.error(err);
        overlay.show(`The rebuilt app crashed while starting, so the page keeps running the previous build.\n\n${describe(err)}`);
      }
    }
  }

  // Wait until the page's own URL answers again, as a restarted server needs a
  // moment, then save the sessions and reload. The page reloads at the URL its
  // sessions start from, so its markup is the one they were recorded on, and the
  // replay takes it to where it was.
  async function leave() {
    if (leaving) return;
    leaving = true;
    for (let tries = 0; tries < 100; tries++) {
      try {
        const answer = await fetch(location.href, { method: 'HEAD', cache: 'no-store' });
        if (answer.status < 500) break;
      } catch {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    await saveSessions();
    if ([...hot.apps].some((app) => (hot.session(app)?.length ?? 0) > 0) && location.href !== startUrl) {
      history.replaceState(history.state, '', startUrl);
    }
    location.reload();
  }
}

function report({ reloaded, replayed, skipped, stopped, restarted, crashed, handedOver, ignored, unsent }) {
  if (restarted) {
    console.info('Joy: reloaded the app and started it over.');
  } else if (reloaded) {
    console.info(`Joy: replayed ${replayed} message${replayed === 1 ? '' : 's'} on the new page to get back where the app was.`);
  } else {
    console.info(`Joy: hot reloaded, replaying ${replayed} message${replayed === 1 ? '' : 's'} to get back where the app was.`);
  }
  if (skipped.length > 0) {
    console.warn('Joy: the replay skipped these messages, which the rebuilt app no longer produces or which it could not tell apart:', skipped);
  }
  if (stopped?.reason === 'request' && reloaded) {
    console.warn(`Joy: the replay stopped before ${stopped.request}, so it is not sent twice. The page carries on from here.`);
  } else if (stopped?.reason === 'asked') {
    console.warn(`Joy: the replay stopped after ${stopped.request}, which it had not sent before. The page carries on from here.`);
  } else if (stopped) {
    const why = {
      gone: 'The rebuilt app no longer produces it.',
      ambiguous: 'A function or opaque value in it prints without its contents, so the replay could not tell which source in the rebuilt app produced it.',
      request: `Replaying it would send ${stopped.request}, which the old app never sent.`,
      unsaved: 'It came with a file or a recording, which did not survive the reload.',
    }[stopped.reason];
    const after = stopped.dropped - 1;
    console.warn(
      `Joy: the replay stopped at ${stopped.text}, leaving out it and the ${after} message${after === 1 ? '' : 's'} after it. ${why}`,
      "To skip such messages instead, set __JOY_HOT__.replay = 'skip'.",
    );
  }
  if (handedOver > 0) {
    console.info(`Joy: ${handedOver} request${handedOver === 1 ? '' : 's'} still on the way will answer the rebuilt app.`);
  }
  if (ignored.length > 0) {
    console.warn('Joy: these requests were still on the way, for messages the replay left out, so their answers will be ignored. The server got them all the same:', ignored);
  }
  if (unsent.length > 0) {
    console.warn('Joy: the replay asked for these requests, which the old app never sent, and did not send them. The app may wait for their answers:', unsent);
  }
  if (crashed) {
    console.error('Joy: the rebuilt app crashed on a replayed message, so it picks up just before that one.', crashed);
  }
}

const describe = (err) => [err, err.cause].filter(Boolean).map(String).join('\n');

// roc's report, over the page. It lives in a shadow root, so the page's styles
// cannot reach it and its own cannot leak out.
const overlay = {
  host: null,
  show(text) {
    if (!globalThis.document) return;
    if (!this.host) {
      this.host = document.createElement('joy-build-report');
      const shadow = this.host.attachShadow({ mode: 'open' });
      shadow.innerHTML = `
        <style>
          div { position: fixed; inset: 0; z-index: 2147483647; overflow: auto; padding: 24px;
                background: rgba(20, 20, 24, 0.94); color: #eee; font: 14px/1.5 ui-monospace, monospace; }
          pre { white-space: pre-wrap; margin: 0; }
          button { position: fixed; top: 12px; right: 16px; font: inherit; color: inherit;
                   background: none; border: 1px solid #888; border-radius: 4px; padding: 2px 10px; cursor: pointer; }
        </style>
        <div><button title="Hide until the next build">close</button><pre></pre></div>`;
      shadow.querySelector('button').onclick = () => this.hide();
    }
    // roc colors its report on a terminal. Drop the escapes.
    this.host.shadowRoot.querySelector('pre').textContent = text.replace(/\x1b\[[0-9;]*m/g, '');
    if (!this.host.isConnected) document.documentElement.append(this.host);
  },
  hide() {
    this.host?.remove();
  },
};
