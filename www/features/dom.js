// The page beyond the app's own view, for the platform's DOM module: focus,
// <dialog> modals, navigation, the browser's back and forward buttons, the
// page title and scrolling.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// helper warn_unmatched
// A selector-addressed operation that matched nothing is a no-op by design
// (the app may focus a field only some pages have), so this is information
// for the developer, not an error: it is how a typo in the selector, or an
// operation that ran before its element existed, shows up.
function warnUnmatched(what, selector) {
  console.warn(`Joy ${what}: nothing on the page matches "${selector}" (or it is not a valid CSS selector), so it did nothing.`);
}

//// op joy/dom/show_modal needs warn_unmatched
defineOperation('joy/dom/show_modal', (args, host) => {
  const selector = args.str();
  if (!host.dom.showModal(selector)) warnUnmatched('DOM.show_modal', selector);
});

//// op joy/dom/close_modal needs warn_unmatched
defineOperation('joy/dom/close_modal', (args, host) => {
  const selector = args.str();
  if (!host.dom.closeModal(selector)) warnUnmatched('DOM.close_modal', selector);
});

//// op joy/dom/focus needs warn_unmatched
defineOperation('joy/dom/focus', (args, host) => {
  const selector = args.str();
  if (!host.dom.focus(selector)) warnUnmatched('DOM.focus', selector);
});

//// op joy/dom/navigate
defineOperation('joy/dom/navigate', (args, host) => host.dom.navigate(args.str()));

//// op joy/dom/push_url
defineOperation('joy/dom/push_url', (args, host) => host.dom.pushUrl(args.str()));

//// op joy/dom/replace_url
defineOperation('joy/dom/replace_url', (args, host) => host.dom.replaceUrl(args.str()));

//// events joy/dom/url_changed
// The new path (path, query and fragment) each time the back or forward
// buttons change the URL.
defineEvents('joy/dom/url_changed', (args, host, emit) =>
  host.dom.onUrlChange(() => emit(new WireWriter().str(host.dom.currentUrl()))));

//// events joy/dom/document_clicks
// The attribute's value on the clicked element, or on its nearest ancestor
// that carries it. Clicks with no such element are not the app's.
defineEvents('joy/dom/document_clicks', (args, host, emit) => {
  const attribute = args.str();
  return host.dom.onGlobal('click', (domEvent) => {
    const value = host.dom.clickedAttr(domEvent, attribute);
    if (value !== null) emit(new WireWriter().str(value));
  });
});

//// op joy/dom/set_title
defineOperation('joy/dom/set_title', (args, host) => host.dom.setTitle(args.str()));

//// op joy/dom/scroll_to
defineOperation('joy/dom/scroll_to', (args, host) => {
  const x = args.u64();
  const y = args.u64();
  host.dom.scrollTo(x, y);
});
