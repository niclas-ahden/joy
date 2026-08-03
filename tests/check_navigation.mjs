// Node harness for navigation: flags seed the query, typing replaces the URL
// in place, the buttons push and navigate.
// Run from the repo root: node tests/check_navigation.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, findTag, htmlBare, navigations, popstate, activeUrlListeners } from './fakedom.mjs';
import { expect } from './harness.mjs';

const bytes = readFileSync('build/navigation.wasm');

const root = new El('#root');
const app = await mount({ wasm: bytes, root, flags: '?q=hats%20on', dom: fakeDom });
expect('flags decode percent-encoded query', htmlBare(root).includes('Current query: hats on'), true);

// Typing percent-encodes and replaces the URL without history entries.
const box = findTag(root, 'input');
box.listeners.input({ target: { value: 'hats off' } });
expect('typed query rendered', htmlBare(root).includes('Current query: hats off'), true);
expect('replace_url! called with encoding', navigations.some((n) => n.kind === 'replace' && n.url === '?q=hats%20off'), true);

// The two buttons.
find(root, 'Push ?demo=push').listeners.click();
expect('push_url! called', navigations.some((n) => n.kind === 'push' && n.url === '?demo=push'), true);
find(root, 'Reload with ?reloaded=1').listeners.click();
expect('navigate! called', navigations.some((n) => n.kind === 'navigate' && n.url === '?reloaded=1'), true);

// Effects with no model change must not repaint (both buttons return none).
expect('query survives the buttons', htmlBare(root).includes('Current query: hats off'), true);

// DOM.on_url_change: Back/Forward (popstate) delivers the new URL to the
// subscription, whose decoder re-derives the query for update.
expect('one URL listener from the subscription', activeUrlListeners().length, 1);
popstate('/diary?q=hats%20on');
expect('Back re-filled the query from the URL', htmlBare(root).includes('Current query: hats on'), true);
popstate('/diary');
expect('a URL without ?q clears the query', htmlBare(root).includes('Current query: '), true);

// Unmount stops the subscription like any other.
app.unmount();
expect('unmount removed the URL listener', activeUrlListeners().length, 0);

