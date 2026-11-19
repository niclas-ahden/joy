// Node harness for an app split into pages, each a module with its own state,
// messages, effects and subscriptions. These are Joy's checks: a page's
// events, effects and subscriptions reach that page through Html's `map`,
// Effect.map_all and Sub.map_all, a page's subscriptions and requests end
// with the page, and the links, the URL and the title follow the app.
//
// The app under test is the spa-pages-expanded template, the app split this
// way that people start from, so these checks fail when the template is gone
// or stops using what they cover. What the template promises on its own (its
// notes, its search, its quote) is checked in
// tests/e2e/spa_pages_expanded_template_test.roc.
// Run from the repo root: node tests/check_spa_pages_expanded.mjs
import { existsSync, readFileSync } from 'node:fs';
import { El, activeGlobalListeners, activeUrlListeners, byId, byRoleAll, fakeDocument, fakeDom, fakeLocation, findTag, htmlBare, linkClick, linkListeners, navigations, popstate } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const template = 'examples/templates/spa-pages-expanded/client/app.roc';
if (!existsSync(template)) {
  throw new Error(`${template} is gone, and Joy's checks of an app split into pages run on it. Point this harness at another app that maps its pages' effects and subscriptions before removing the template.`);
}

const { mount } = await appRuntime('spa-pages-expanded');

// Captured timers (the search's debounce uses setTimeout) and requests (the
// Quote page's Http.get), answered when the test says so.
const timeouts = [];
globalThis.setTimeout = (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; };
globalThis.clearTimeout = () => {};
const requests = [];
globalThis.fetch = (url) => new Promise((resolve) => { requests.push({ url, resolve }); });
const answer = (request, quote) => request.resolve({
  status: 200,
  headers: new Headers({ 'content-type': 'application/json' }),
  arrayBuffer: async () => new TextEncoder().encode(JSON.stringify([quote])).buffer,
});
// An effect answers through a promise, a few microtasks after its timer or
// its response.
const settled = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };

const site = 'http://localhost';
fakeLocation.url = `${site}/`;
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('spa-pages-expanded')), root, flags: `${site}/`, dom: fakeDom });

const heading = () => htmlBare(findTag(root, 'h1')).replace(/<[^>]+>/g, '');
const current = () => byRoleAll(findTag(root, 'nav'), 'link').filter((a) => a.attrs.get('aria-current') === 'page').map((a) => htmlBare(a)).join(',');
const keyListeners = () => activeGlobalListeners().filter((l) => l.event === 'keydown');
const type = (id, value) => byId(root, id).listeners.input({ target: { value } });
const go = (path) => linkClick(root, `${site}${path}`);

// --- The URL in the flags opens its page, and the title is set ---

expect('the flags URL opened the notes page', heading(), 'Notes');
expect('the title effect ran at boot', fakeDocument.title, 'Notes - Joy app');
expect('the menu marks the page', current(), 'Notes');
expect('the app took over its links', linkListeners.filter((l) => l.active && l.root === root).length, 1);
expect('the app hears the URL change', activeUrlListeners().length, 1);

// --- Html's map: a page's events reach the page ---

// The notebook starts with a few notes of its own.
const notes = () => byRoleAll(findTag(root, 'ul'), 'link').map((a) => htmlBare(a)).join(',');
const all = `${notes()},Buy milk,Call mum`;
type('note', 'Buy milk');
findTag(root, 'form').listeners.submit({ preventDefault: () => {} });
type('note', 'Call mum');
findTag(root, 'form').listeners.submit({ preventDefault: () => {} });
expect('a mapped submit reached the page', notes(), all);
expect('a mapped input reached the page', byId(root, 'note').attrs.get('value'), '');

// --- Effect.map_all: a page's effect answers to the page ---

type('search', 'milk');
const debounce = timeouts.find((t) => t.ms === 300);
expect('the page asked for a timer', debounce !== undefined, true);
expect('nothing is filtered until the timer fires', notes(), all);
debounce.fn();
await settled();
expect('the mapped timer reached the page', notes(), 'Buy milk');

// --- Sub.map_all: a page's subscription reaches the page, and ends with it ---

expect('the page subscribed to the keyboard', keyListeners().length, 1);
keyListeners()[0].fn({ key: 'Escape', code: 'Escape', preventDefault: () => {} });
expect('the mapped key press reached the page', notes(), all);
expect('the page dropped its subscription', keyListeners().length, 0);

type('search', 'mum');
expect('the page subscribed again', keyListeners().length, 1);
const pushes = () => navigations.filter((n) => n.kind === 'push').map((n) => n.url).join(',');
go('/about');
expect('a link click pushed its URL', pushes(), `${site}/about`);
expect('the pushed URL opened its page', heading(), 'About');
expect('the title follows the page', fakeDocument.title, 'About - Joy app');
expect('the menu follows the page', current(), 'About');
expect('leaving a page ends its subscription', keyListeners().length, 0);

// --- Back opens the page again, and only the app's state is still there ---

popstate(`${site}/`);
expect('Back opened the notes page', heading(), 'Notes');
expect('the app kept its notes', notes(), all);
expect('the page started over', byId(root, 'search').attrs.get('value'), '');
expect('a page that started over has no subscription', keyListeners().length, 0);

// --- An answer for a page that is gone changes nothing ---

go('/quote');
expect('opening a page ran its effect', requests.length, 1);
expect('the page waits for its answer', htmlBare(root).includes('Loading a quote'), true);
go('/about');
const before = htmlBare(root);
answer(requests[0], 'Too late.');
await settled();
expect('a late answer changed nothing', htmlBare(root), before);

go('/quote');
expect('the page asks again when it is opened again', requests.length, 2);
answer(requests[1], 'Never half-ass two things.');
await settled();
expect('the mapped answer reached the page', htmlBare(root).includes('Never half-ass two things.'), true);

// --- A URL that is not a page, and a link that is not the app's ---

popstate(`${site}/nowhere`);
expect('an unknown URL shows the not found page', heading(), 'Not found');
expect('with its title', fakeDocument.title, 'Not found - Joy app');
expect('and no page marked', current(), '');
go('/file.pdf');
expect('a link that is not a page loads as links do', navigations.some((n) => n.kind === 'navigate' && n.url === `${site}/file.pdf`), true);

// --- Unmount ends the app's own subscriptions ---

app.unmount();
expect('unmount removed the URL listener', activeUrlListeners().length, 0);
expect('unmount gave the links back', linkListeners.filter((l) => l.active && l.root === root).length, 0);
