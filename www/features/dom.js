// The page beyond the app's own view, for the platform's DOM module: focus,
// <dialog> modals, clicks on the document, the page title and scrolling.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// helper warn_unmatched
// A selector-addressed effect that matched nothing is a no-op by design
// (the app may focus a field only some pages have), so this is information
// for the developer, not an error: it is how a typo in the selector, or an
// effect that ran before its element existed, shows up.
function warnUnmatched(what, selector) {
  console.warn(`Joy ${what}: nothing on the page matches "${selector}" (or it is not a valid CSS selector), so it did nothing.`);
}

//// effect joy/dom/show_modal needs warn_unmatched
defineEffect('joy/dom/show_modal', (args, host) => {
  const selector = args.str();
  if (!host.dom.showModal(selector, host.root())) warnUnmatched('DOM.show_modal', selector);
});

//// effect joy/dom/close_modal needs warn_unmatched
defineEffect('joy/dom/close_modal', (args, host) => {
  const selector = args.str();
  if (!host.dom.closeModal(selector, host.root())) warnUnmatched('DOM.close_modal', selector);
});

//// effect joy/dom/focus needs warn_unmatched
defineEffect('joy/dom/focus', (args, host) => {
  const selector = args.str();
  if (!host.dom.focus(selector, host.root())) warnUnmatched('DOM.focus', selector);
});

//// subscription joy/dom/document_clicks
// The attribute's value on the clicked element, or on its nearest ancestor
// that carries it. Clicks with no such element are not the app's.
defineSubscription('joy/dom/document_clicks', (args, host, emit) => {
  const attribute = args.str();
  return host.dom.onGlobal('click', (domEvent) => {
    const value = host.dom.clickedAttr(domEvent, attribute);
    if (value !== null) emit(new WireWriter().str(value));
  });
});

//// effect joy/dom/set_title
defineEffect('joy/dom/set_title', (args, host) => host.dom.setTitle(args.str()));

//// effect joy/dom/scroll_to
defineEffect('joy/dom/scroll_to', (args, host) => {
  const x = args.u64();
  const y = args.u64();
  host.dom.scrollTo(x, y);
});
