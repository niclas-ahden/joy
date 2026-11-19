// Node harness for the navigation example: a link pushes its URL, the page
// on screen follows the URL, also on Back, and the two buttons ask for a
// replace and for a full page load.
// Run from the repo root: node tests/check_navigation.mjs
import { readFileSync } from 'node:fs';
import { El, byId, fakeDom, fakeLocation, htmlBare, linkClick, navigations, popstate } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('navigation');

const site = 'http://localhost';
fakeLocation.url = `${site}/`;
const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('navigation')), root, flags: '', dom: fakeDom });

const shown = (id) => htmlBare(byId(root, id)).replace(/<[^>]+>/g, '');
const asked = (kind) => navigations.filter((n) => n.kind === kind).map((n) => n.url).join(',');

expect('starts on Home', shown('page'), 'Home');
expect('one page opened', shown('opened'), 'Pages opened: 1');

linkClick(root, `${site}/about`);
expect('a link pushed its URL', asked('push'), `${site}/about`);
expect('the pushed URL opened its page', shown('page'), 'About');
expect('and was counted', shown('opened'), 'Pages opened: 2');

popstate(`${site}/`);
expect('Back opened the page before', shown('page'), 'Home');

byId(root, 'skip').listeners.click();
expect('the button replaced the URL', asked('replace'), '/contact');
expect('the replaced URL opened its page', shown('page'), 'Contact');
expect('with no new step in the history', asked('push'), `${site}/about`);

linkClick(root, `${site}/nope`);
expect('a URL that is no page says so', shown('page'), 'Not found');

byId(root, 'reload').listeners.click();
expect('the other button asked for a full page load', asked('navigate'), '/');
