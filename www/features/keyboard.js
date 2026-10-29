// Keys pressed anywhere on the page, for the platform's Keyboard module.
// The key filter and preventDefault are the subscription's own data, so they
// run here without entering the app.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// events joy/keyboard/keys
// Each event is the key, the physical code, and the modifiers and repeat
// packed into a byte (1 ctrl, 2 shift, 4 alt, 8 meta, 16 repeat, 32
// is_composing).
defineEvents('joy/keyboard/keys', (args, host, emit) => {
  const event = args.str();
  const keys = [];
  for (let n = args.u32(); n > 0; n--) keys.push(args.str());
  const preventDefault = args.bool();
  return host.dom.onGlobal(event, (domEvent) => {
    const info = host.dom.eventKeyInfo(domEvent);
    if (keys.length > 0 && !keys.includes(info.key)) return;
    if (preventDefault) domEvent.preventDefault?.();
    const flags =
      (info.ctrl ? 1 : 0) | (info.shift ? 2 : 0) | (info.alt ? 4 : 0) | (info.meta ? 8 : 0) | (info.repeat ? 16 : 0) |
      (info.isComposing ? 32 : 0);
    emit(new WireWriter().str(info.key).str(info.code).u8(flags));
  });
});
