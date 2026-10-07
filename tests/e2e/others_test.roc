# Nodes others put among the app's, in a real browser: a custom element
# whose connectedCallback inserts next to itself while the runtime is still
# inserting it, a MutationObserver that puts a control in front of every
# video the way a speed-control extension does, and a script's nodes added
# between paints (an ad among keyed items, a map's tiles in a container the
# app leaves empty, a badge in an empty panel). Every message of the others
# app must patch the app's own nodes without a throw and leave the others'
# where they are, and the page without them must be a twin app's page, a
# second instance nobody touches.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("others", "#app .rotate")?

	Assert.eq(page.evaluate!(drive)?, "ok") ? |e| OthersBrokeThePage(Str.inspect(e))

	browser.close!()?
	Ok({})
}

## Set the others loose on the app, run every message in it and in a twin,
## and report "ok" or what went wrong.
drive : Str
drive =
	\\(async () => {
	\\  const app = document.getElementById('app');
	\\  const errors = [];
	\\  window.addEventListener('error', (e) => errors.push(e.message));
	\\
	\\  // A web component that puts a rule in front of itself on connect,
	\\  // which runs inside the insert that connects it.
	\\  customElements.define('x-note', class extends HTMLElement {
	\\    connectedCallback() {
	\\      if (this.previousElementSibling?.localName !== 'hr') this.before(document.createElement('hr'));
	\\    }
	\\  });
	\\  // A speed-control extension: a control in front of every video.
	\\  new MutationObserver(() => {
	\\    for (const v of app.querySelectorAll('video')) {
	\\      if (v.previousElementSibling?.localName !== 'vsc-controller') v.before(document.createElement('vsc-controller'));
	\\    }
	\\  }).observe(app, { childList: true, subtree: true });
	\\  // A script's nodes between paints.
	\\  const theirs = (tag, cls) => Object.assign(document.createElement(tag), { className: cls });
	\\  const items = app.querySelector('.items');
	\\  const ad = items.insertBefore(theirs('div', 'ad'), items.children[2]);
	\\  const tiles = app.querySelector('.map').appendChild(theirs('canvas', 'tiles'));
	\\  const badge = app.querySelector('.panel').appendChild(theirs('i', 'badge'));
	\\
	\\  // The twin: the same app in a second root nobody else touches.
	\\  const { mount } = await import('./runtime.js');
	\\  const twinRoot = document.body.appendChild(document.createElement('div'));
	\\  await mount({ wasm: './app.wasm', root: twinRoot, flags: '' });
	\\
	\\  // The page as the app made it: everything of others' taken out.
	\\  const own = (root) => {
	\\    const copy = root.cloneNode(true);
	\\    for (const n of copy.querySelectorAll('vsc-controller, hr, .ad, .tiles, .badge')) n.remove();
	\\    return copy.innerHTML;
	\\  };
	\\  const settle = () => new Promise((ok) => setTimeout(ok, 0));
	\\  const steps = ['count', 'rotate', 'add', 'swap', 'rotate', 'spin', 'drop', 'open', 'spin', 'add', 'open', 'swap', 'fresh', 'rotate', 'open', 'drop', 'spin', 'fresh', 'open', 'count'];
	\\  const problems = [];
	\\  for (const [k, cls] of steps.entries()) {
	\\    app.querySelector('.' + cls).click();
	\\    twinRoot.querySelector('.' + cls).click();
	\\    await settle(); // lets the extension's observer run, between paints
	\\    if (own(app) !== own(twinRoot)) problems.push('step ' + (k + 1) + ' (' + cls + '): the page differs from the twin');
	\\  }
	\\  for (const [name, node] of [['ad', ad], ['tiles', tiles], ['badge', badge]]) {
	\\    if (!app.contains(node)) problems.push('the ' + name + ' was removed');
	\\  }
	\\  if (app.querySelectorAll('.panel hr').length === 0) problems.push('the custom element never got to insert');
	\\  const media = [...app.querySelector('.media').children].map((n) => n.localName).join(' ');
	\\  if (media !== 'vsc-controller video') problems.push('the media holds ' + media);
	\\  return [...errors, ...problems].join('; ') || 'ok';
	\\})()
