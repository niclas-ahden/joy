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
// The app's pending debounces by key. Re-arming or cancelling one ends its
// call without an answer, which releases the app's callback.
function debouncesOf(host) {
  return host.own('debounces', () => {
    const debounces = new Map(); // key -> { handle, resolve }
    host.onUnmount(() => { for (const key of [...debounces.keys()]) dropDebounce(debounces, key); });
    return debounces;
  });
}

function dropDebounce(debounces, key) {
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
  const debounces = debouncesOf(host);
  dropDebounce(debounces, key);
  return new Promise((resolve) => {
    const handle = setTimeout(() => {
      debounces.delete(key);
      resolve(new WireWriter().i64(Date.now()));
    }, ms);
    debounces.set(key, { handle, resolve });
  });
});

//// op joy/time/cancel needs debounces
defineOperation('joy/time/cancel', (args, host) => dropDebounce(debouncesOf(host), args.str()));
