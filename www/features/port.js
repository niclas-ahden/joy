// Ports to the page's own JavaScript, for the platform's Port module. The
// embedder registers outgoing handlers with app.onPort and sends incoming
// values with app.sendPort (see the runtime's mount handle), which reach the
// app through these operations.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// op joy/port/send
defineOperation('joy/port/send', (args, host) => {
  const name = args.str();
  const value = args.str();
  host.outPort(name)?.(value); // unregistered names are a no-op
});

//// events joy/port/listen
defineEvents('joy/port/listen', (args, host, emit) =>
  host.listenPort(args.str(), (value) => emit(new WireWriter().str(String(value)))));
