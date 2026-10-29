// Node harness for DOM.set_title, DOM.scroll_to, DOM.on_document_click,
// Clipboard.write_text and Clipboard.write_text_of: the title from init and
// from an update, a scroll after a page switch, clicks on HTML around the
// app's root, and each answer the clipboard can give. The fake DOM records
// the title and the scrolls, and navigator.clipboard is stubbed per case.
// Run from the repo root: node tests/check_document.mjs
import { readFileSync } from 'node:fs';
import { El, Text, activeGlobalListeners, fakeDocument, fakeDom, find, htmlBare, scrolls } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('document');

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('document')), root, flags: '', dom: fakeDom });

expect('init names the page', fakeDocument.title, 'Page 1');
expect('nothing scrolled yet', scrolls.length, 0);

find(root, 'Next').listeners.click();
expect('the update renamed the page', fakeDocument.title, 'Page 2');
expect('the switch scrolled to the top', JSON.stringify(scrolls), JSON.stringify([{ x: 0, y: 0 }]));
expect('the view followed', htmlBare(root).includes('page 2'), true);

// The clipboard answers after a turn of the event loop, like the browser's.
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
const stubClipboard = (clipboard) =>
  Object.defineProperty(globalThis.navigator, 'clipboard', { value: clipboard, configurable: true });
const copy = async () => {
  find(root, 'Copy').listeners.click();
  await settle();
};
// The paragraph after "Copy" is what the clipboard answered.
const copiedText = () => (htmlBare(root).match(/<button>Copy<\/button><p>([^<]*)<\/p>/) ?? [])[1];

const written = [];
stubClipboard({ writeText: async (s) => { written.push(s); } });
await copy();
expect('the text reached the clipboard', JSON.stringify(written), JSON.stringify(['roc build']));
expect('a write that worked says so', copiedText(), 'copied the text');

stubClipboard({
  writeText: async () => {
    throw new DOMException('Document is not focused.', 'NotAllowedError');
  },
});
await copy();
expect('a refused write is NotAllowed', copiedText(), 'failed the text: NotAllowed');

stubClipboard(undefined);
globalThis.isSecureContext = false;
await copy();
expect('a page that is not secure is Insecure', copiedText(), 'failed the text: Insecure');

globalThis.isSecureContext = true;
await copy();
expect('a browser without the API is Unsupported', copiedText(), 'failed the text: Unsupported');

// The page's own HTML beside the root: an element carrying data-pick with
// a span inside it and another data-pick inside that, an element without
// the attribute, and the #source the second copy button copies.
const page = fakeDom.createElement('body');
page.parent = new El('#document');
const el = (tag, attrs, children = []) => {
  const node = fakeDom.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) node.attrs.set(k, v);
  for (const child of children) fakeDom.append(node, child);
  return node;
};
const span = el('span', {});
const inner = el('em', { 'data-pick': 'inner' });
const plain = el('p', {});
const source = el('pre', { id: 'source' }, [new Text('joy '), el('b', {}, [new Text('dev')])]);
fakeDom.append(page, el('div', { 'data-pick': 'outer' }, [span, inner]));
fakeDom.append(page, plain);
fakeDom.append(page, source);

const clicks = () => activeGlobalListeners().filter((l) => l.event === 'click');
const click = (target) => { for (const l of clicks()) l.fn({ target }); };
const picked = () => (htmlBare(root).match(/<p>picked: ([^<]*)<\/p>/) ?? [])[1];

expect('one document listener for clicks', clicks().length, 1);
click(plain);
expect('a click on HTML without the attribute is not the app\'s', picked(), 'nothing');
click(span);
expect('a click inside an element with the attribute names it', picked(), 'outer');
click(inner);
expect('the nearest element with the attribute wins', picked(), 'inner');

const copySource = async () => {
  find(root, 'Copy the source').listeners.click();
  await settle();
};
written.length = 0;
stubClipboard({ writeText: async (s) => { written.push(s); } });
await copySource();
expect('the element\'s text reached the clipboard', JSON.stringify(written), JSON.stringify(['joy dev']));
expect('a copy of an element that worked says so', copiedText(), 'copied #source');

source.parent = null;
await copySource();
expect('an element that is not there is NotFound', copiedText(), 'failed #source: NotFound');
expect('and nothing more was written', written.length, 1);
