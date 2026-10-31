// What hot reloading adds to runtime.js, in the runtime.js ./joy dev serves. An
// app never ships any of this: JoyRuntime.hot in tools/runtime puts each section
// in at the comment of its name in runtime.js, and the `module` section at the
// end. These are parts of runtime.js, not a module, so they read its names.

//// runtime
// Inside makeRuntime. Every call into the host goes through its function, so
// wrapping the function sends every call through this table, which Joy's dev
// module wraps in turn. An observer's dispatch passes the node it watches, and a
// handler's the DOM event.
const hotOps = { dispatch, dispatchValue, dispatchKey, dispatchPointer, deliverFile, dispatchVisible: dispatch, dispatchBytes, dispatchSubBytes, endCall, drainLog, runEffect };
dispatch = (id, from) => (from !== undefined && from.currentTarget === undefined ? hotOps.dispatchVisible(id, from) : hotOps.dispatch(id, from));
dispatchValue = (...args) => hotOps.dispatchValue(...args);
dispatchKey = (...args) => hotOps.dispatchKey(...args);
dispatchPointer = (...args) => hotOps.dispatchPointer(...args);
deliverFile = (...args) => hotOps.deliverFile(...args);
dispatchBytes = (...args) => hotOps.dispatchBytes(...args);
dispatchSubBytes = (...args) => hotOps.dispatchSubBytes(...args);
endCall = (...args) => hotOps.endCall(...args);
drainLog = (...args) => hotOps.drainLog(...args);
runEffect = (...args) => hotOps.runEffect(...args);
handle.dispatch = (id) => dispatch(id);
handle.dispatchValue = (id, value) => dispatchValue(id, value);

// Give `live`, an element already on the page, what this runtime keeps on
// `fresh`, an element of its own view that `live` takes the place of (see goLive
// in www/hot.js): its handlers, the props it declares and its visibility observer.
// `seen` says the app this runtime succeeds was told `live` is in view, when it
// is, so the observer does not tell this one again.
const adopt = (fresh, live, seen) => {
  for (const [name, d] of fresh[EVENTS] ?? []) if (d) setHandler(live, name, d);
  if (fresh[LIVE]) live[LIVE] = fresh[LIVE];
  const v = nodeVis.get(fresh);
  if (v) {
    v.disconnect();
    nodeVis.delete(fresh);
    const disconnect = dom.observeVisibility(live, v.margin, () => {
      const cur = nodeVis.get(live);
      if (cur) dispatch(cur.id, live);
    }, seen);
    nodeVis.set(live, { margin: v.margin, key: v.key, id: v.id, disconnect });
  }
};

// What Joy's dev module needs to record this app and replay it into a rebuilt one
// (see www/hot.js).
handle.hooks = {
  exports,
  dom,
  ops: hotOps,
  str,
  start,
  perform,
  retire: stop,
  hears,
  reader: (bytes) => new WireReader(bytes),
  adopt,
  pin: restoreControl,
  listeners: [domListener, compositionListener],
  nodes: () => nodeList,
  handlers: (node) => node[EVENTS],
  visibility: (node) => nodeVis.get(node),
  root: () => root,
  // The view now lives under `node`, which Joy's dev module made match it, with
  // each node that was kept named in `kept`.
  setRoot: (node, kept) => {
    root = node;
    nodeList = nodeList.map((n) => kept.get(n) ?? n);
  },
  // What outlives one wasm instance when the app is hot reloaded into another:
  // outgoing port handlers, picked files and their ids, what to run on unmount,
  // what features keep for the app, and the perf counters.
  shared: () => ({ outPorts, files, fileIds, unmountHooks, owned, perf }),
  share: (from) => {
    ({ outPorts, files, fileIds, unmountHooks, owned, perf } = from);
  },
};

//// mount
// Inside mount, once the page's setup has run. Calls go to whichever runtime is
// current, so the handle the page holds keeps working when the app is hot
// reloaded. Joy's dev module records the app from its first message, so it takes
// the app on before `init` runs. Here it gets what swapping in a rebuilt module
// takes, and it answers with what starts the app when it has a session to pick up.
Object.defineProperty(app, 'instance', { get: () => instance, enumerable: true });
app.dispatch = (id) => rt.dispatch(id);
app.dispatchValue = (id, value) => rt.dispatchValue(id, value);
app.sendPort = (name, value) => rt.sendPort(name, value);
app.onPort = (name, fn) => rt.onPort(name, fn);
app.unmount = () => rt.unmount();
const resume = globalThis.__JOY_HOT__?.adopt(app, {
  wasm,
  flags,
  dom,
  root,
  runtime: () => rt,
  compile: (next) => hotCompile(next),
  // A rebuilt runtime, rendering into a root of its own until it takes over.
  spawn: async (next) => {
    const fresh = await WebAssembly.instantiate(next, { env: { joy_bench_now: () => performance.now() } });
    const runtime = makeRuntime(fresh.exports, dom, dom.createElement('div'));
    runtime.hooks.share(rt.hooks.shared());
    return { instance: fresh, runtime };
  },
  replace: (next) => {
    rt = next.runtime;
    instance = next.instance;
  },
});
if (resume) {
  await resume();
  return app;
}

//// module
// The module at `wasm`, a URL or the bytes, as the page's server has it now.
async function hotCompile(wasm) {
  if (typeof wasm !== 'string') return WebAssembly.compile(wasm);
  const res = await fetch(wasm, { cache: 'no-store' });
  if (!res.ok) throw new Error(`reload: could not fetch ${wasm} (${res.status} ${res.statusText})`);
  if (res.headers.get('content-type')?.startsWith('application/wasm')) return WebAssembly.compileStreaming(res);
  return WebAssembly.compile(await res.arrayBuffer());
}

// An observer that leaves out its first report, of the state the node starts in,
// when `seen` says the app has had that report already.
browserDom.observeVisibility = (node, rootMargin, fire, seen) => {
  const observer = new IntersectionObserver(
    (entries) => entries.forEach((entry) => {
      if (entry.isIntersecting && !seen) fire();
      seen = false;
    }),
    { rootMargin },
  );
  observer.observe(node);
  return () => observer.disconnect();
};
