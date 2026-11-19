// The URL, for the platform's Navigation module: loading a page, changing
// the URL in place, the browser's Back and Forward buttons and clicks on the
// app's links.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// effect joy/navigation/navigate
defineEffect('joy/navigation/navigate', (args, host) => host.dom.navigate(args.str()));

//// effect joy/navigation/push_url
defineEffect('joy/navigation/push_url', (args, host) => host.dom.pushUrl(args.str()));

//// effect joy/navigation/replace_url
defineEffect('joy/navigation/replace_url', (args, host) => host.dom.replaceUrl(args.str()));

//// subscription joy/navigation/url_changed
// The page's whole address each time the URL changes: by Back and Forward,
// by a link to a #fragment of the page, and by a push_url or replace_url of
// any app on the page.
defineSubscription('joy/navigation/url_changed', (args, host, emit) =>
  host.dom.onUrlChange(() => emit(new WireWriter().str(host.dom.currentUrl()))));

//// subscription joy/navigation/link_clicks
// The whole address of a link of this site clicked inside the
// app, which the app then answers for (see onLinkClick).
defineSubscription('joy/navigation/link_clicks', (args, host, emit) =>
  host.dom.onLinkClick(host.root(), (url) => emit(new WireWriter().str(url))));
