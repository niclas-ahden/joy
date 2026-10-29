// Timers for the platform's Time module: a one-shot, a recurring one while
// subscribed, and a keyed debounce. Each fires with the time in ms since
// the Unix epoch.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// op joy/time/after
defineOperation('joy/time/after', (args) => {
  const ms = args.u32();
  return new Promise((resolve) => setTimeout(() => resolve(new WireWriter().i64(Date.now())), ms));
});

//// events joy/time/every
defineEvents('joy/time/every', (args, host, emit) => {
  const handle = setInterval(() => emit(new WireWriter().i64(Date.now())), args.u32());
  return () => clearInterval(handle);
});

//// helper debounces
// Pending debounces by key. Re-arming or cancelling one ends its call
// without an answer, which releases the app's callback.
const debounces = new Map(); // key -> { handle, resolve }
let clearsOnUnmount = false;

function dropDebounce(key) {
  const pending = debounces.get(key);
  if (!pending) return;
  clearTimeout(pending.handle);
  debounces.delete(key);
  pending.resolve(NO_REPLY);
}

//// op joy/time/debounce needs debounces
defineOperation('joy/time/debounce', (args, host) => {
  const key = args.str();
  const ms = args.u32();
  if (!clearsOnUnmount) {
    clearsOnUnmount = true;
    host.onUnmount(() => { for (const key of [...debounces.keys()]) dropDebounce(key); });
  }
  dropDebounce(key);
  return new Promise((resolve) => {
    const handle = setTimeout(() => {
      debounces.delete(key);
      resolve(new WireWriter().i64(Date.now()));
    }, ms);
    debounces.set(key, { handle, resolve });
  });
});

//// op joy/time/cancel needs debounces
defineOperation('joy/time/cancel', (args) => dropDebounce(args.str()));
