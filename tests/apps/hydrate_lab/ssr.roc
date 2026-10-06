app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	# The same joy-html app.roc uses, so the server and the client render
	# with one implementation.
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html
import pf.OsStr
import pf.Path
import pf.Stderr
import Lab

## The server half of the hydration lab: renders Lab's view with joy-html
## into one page per scenario, the way a fullstack server would, for the
## browser tests to boot app.roc over (tests/e2e/hydrate_*_test.roc).
## build.roc runs it after building the app:
##
##     roc tests/apps/hydrate_lab/ssr.roc build/<opt>/ssr/hydrate_lab
##
## and www/serve.mjs serves each page at /hydrate_lab/<name> (index at /).
## Each scenario names the model the server renders and the model the
## client boots from. They differ where a test wants the server wrong.
main! = |raw_args|
	match raw_args.map(|arg| OsStr.display(arg)) {
		[out_dir] => write_pages!(out_dir)
		_ => {
			Stderr.line!("usage: roc tests/apps/hydrate_lab/ssr.roc <out dir>")?
			Err(Exit(1))
		}
	}

pages : List({ name : Str, server : Lab.Model, client : Lab.Model })
pages = [
	# The server and the client agree: a clean claim.
	{ name: "index", server: Lab.default, client: Lab.default },
	# The server rendered stale attributes: a disabled button, an attribute
	# and a class the client's first render does not have.
	{ name: "stale", server: { ..Lab.default, locked: Bool.True, stale: Bool.True }, client: Lab.default },
	# Both agree, but on rows straight in a table, which the parser wraps.
	{ name: "bare", server: { ..Lab.default, bare_rows: Bool.True }, client: { ..Lab.default, bare_rows: Bool.True } },
	# Both agree, on a template and a <meta>, each with a `content` property.
	{ name: "content", server: { ..Lab.default, contents: Bool.True }, client: { ..Lab.default, contents: Bool.True } },
]

write_pages! = |out_dir| {
	Path.create_all!(Path.utf8(out_dir))?
	_ = pages.map_try!(|page| Path.write_utf8!(Path.utf8("${out_dir}/${page.name}.html"), document(page.server, page.client)))?
	Ok({})
}

## A page in the shape a fullstack server sends: the rendered view in #app,
## the client's model as JSON in an inert template (its text is escaped like
## any text and decodes back exactly), and the loader, which also leaves the
## browser tests their helpers on window (see loader).
document : Lab.Model, Lab.Model -> Str
document = |server, client| {
	app_html = Html.render(Lab.view(server))
	flags_html = Html.render(Html.text(Lab.encode(client)))
	page =
		\\<!DOCTYPE html>
		\\<html lang="en">
		\\<head><meta charset="utf-8" /><title>Joy hydration lab</title></head>
		\\<body>
		\\<div id="app">${app_html}</div>
		\\<template id="joy-model">${flags_html}</template>
		\\<script type="module">
		\\${loader}
		\\</script>
		\\</body>
		\\</html>
	page
}

## The page's script. Plain concatenation, no template literals, since their
## dollar-brace would read as Roc interpolation here.
loader : Str
loader =
	\\import { mount } from './runtime.js';
	\\
	\\const flags = document.getElementById('joy-model').content.textContent;
	\\const root = document.getElementById('app');
	\\
	\\// A tree as comparable lines: per element its namespace, name and every
	\\// attribute with the attribute's namespace, per text node its data.
	\\// `parsed` merges adjacent text and drops empty text, which is all the
	\\// parser can hand back from markup.
	\\function entries(node, parsed, path, out) {
	\\  let kids = Array.from(node.childNodes).filter((n) => n.nodeType === 1 || n.nodeType === 3);
	\\  if (parsed) {
	\\    const merged = [];
	\\    for (const n of kids) {
	\\      if (n.nodeType === 3) {
	\\        if (n.data === '') continue;
	\\        const last = merged[merged.length - 1];
	\\        if (last && last.nodeType === 3) { merged[merged.length - 1] = document.createTextNode(last.data + n.data); continue; }
	\\      }
	\\      merged.push(n);
	\\    }
	\\    kids = merged;
	\\  }
	\\  kids.forEach((n, i) => {
	\\    const at = path + '/' + i;
	\\    if (n.nodeType === 3) { out.push(at + ' text ' + JSON.stringify(n.data)); return; }
	\\    const attrs = Array.from(n.attributes).map((a) => (a.namespaceURI || '') + '|' + a.name + '=' + JSON.stringify(a.value)).sort();
	\\    out.push(at + ' ' + n.namespaceURI + ' ' + n.localName + ' ' + attrs.join(' '));
	\\    entries(n, parsed, at, out);
	\\  });
	\\  return out;
	\\}
	\\
	\\// The first differences between two trees' children, [] when they match.
	\\window.labDiff = (a, b, parsed = false) => {
	\\  const x = entries(a, parsed, '', []);
	\\  const y = entries(b, parsed, '', []);
	\\  const diffs = [];
	\\  for (let i = 0; i < Math.max(x.length, y.length) && diffs.length < 5; i++) {
	\\    if (x[i] !== y[i]) diffs.push((x[i] || '(none)') + '  vs  ' + (y[i] || '(none)'));
	\\  }
	\\  return diffs;
	\\};
	\\
	\\// A fresh client build of the same flags, never hydrated.
	\\window.labFresh = async () => {
	\\  const div = document.createElement('div');
	\\  const fresh = await mount({ wasm: './app.wasm', root: div, flags });
	\\  fresh.unmount();
	\\  return div;
	\\};
	\\
	\\// The claimed page against a fresh build of the same flags.
	\\window.labAgainstFresh = async () => window.labDiff(root, await window.labFresh());
	\\
	\\// A node against what the parser makes of its own markup, which is
	\\// what a server sending that markup would get.
	\\window.labRoundTrip = (node) => {
	\\  const a = document.createElement('div');
	\\  a.appendChild(node.cloneNode(true));
	\\  const b = document.createElement('div');
	\\  b.innerHTML = node.outerHTML;
	\\  return window.labDiff(a, b, true);
	\\};
	\\
	\\window.app = await mount({ wasm: './app.wasm', root, flags, hydrate: true });
	\\root.setAttribute('data-booted', '');
