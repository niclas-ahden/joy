// Node harness for examples/spa_pages: an app split into page modules. Each page
// owns its Model and Msg, and the app wraps them with Html.map, Effect.map
// and Sub.map. Checks that every page's messages reach that page and only
// it, that a page's state survives a visit to another page, and that the clock's
// boot effect and tick subscription are routed through the wrappers.
// Run from the repo root: node tests/check_spa_pages.mjs
import { readFileSync } from 'node:fs';
import { El, byId, byRole, byRoleAll, fakeDom, htmlBare } from './fakedom.mjs';
import { appRuntime, expect, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('spa_pages');

// Captured timers (the boot Effect uses setTimeout, the tick Sub setInterval).
// Every firing reads Date.now(), stubbed so the clock text is predictable.
const timeouts = [];
const intervals = [];
let cleared = 0;
let now = 0;
globalThis.Date.now = () => now;
globalThis.setTimeout = (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; };
// A Time operation answers through a promise, a microtask after its timer.
const settled = () => new Promise((r) => setImmediate(r));
globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
globalThis.clearInterval = () => { cleared += 1; };

const root = new El('#root');
await mount({ wasm: readFileSync(wasmPath('spa_pages')), root, flags: '', dom: fakeDom });

const textOf = (id) => htmlBare(byId(root, id)).replace(/<[^>]+>/g, '');
const click = (label) => byRole(root, 'button', label).listeners.click();
const goTo = (page) => byRoleAll(byId(root, 'pages'), 'button', page)[0].listeners.click();

// --- Boot: the counter page shows, the clock's boot effect and tick were mapped ---

expect('counter page shows at boot', byId(root, 'counter') !== null && byId(root, 'clock') === null, true);
expect('count starts at 0', textOf('count'), '0');
expect('clock boot effect scheduled a timeout', timeouts.length === 1 && timeouts[0].ms === 0, true);
expect('clock tick subscription started an interval', intervals.length === 1 && intervals[0].ms === 1000, true);

// --- Counter: messages route to the counter page, state transforms ---

click('+'); click('+'); click('-');
expect('count after +,+,-', textOf('count'), '1');
expect('clicks counted', textOf('clicks'), '3 clicks so far');
byId(root, 'step').listeners.input({ target: { value: '5' } });
click('+');
expect('step changed the increment', textOf('count'), '6');
byId(root, 'step').listeners.input({ target: { value: 'nope' } });
expect('a non-number leaves the step alone', byId(root, 'step').attrs.get('value'), '5');
click('Reset');
expect('reset clears the count', textOf('count'), '0');
expect('reset clears the clicks', textOf('clicks'), '0 clicks so far');
click('+');
expect('step survives a reset', textOf('count'), '5');

// --- Clock: the mapped boot effect and ticks land on the clock model, even while hidden ---

// The boot timer fires while the counter page is showing. Its Tick must reach
// the clock model, not the counter.
now = 3_723_000;
timeouts[0].fn();
await settled();
expect('boot tick did not touch the counter', textOf('count'), '5');
goTo('Clock');
expect('clock page shows', byId(root, 'clock') !== null && byId(root, 'counter') === null, true);
expect('boot tick set the time', textOf('time'), '01:02:03 UTC');
now = 3_724_000;
intervals[0].fn();
expect('interval tick advances the time', textOf('time'), '01:02:04 UTC');
click('Lap'); click('Lap');
expect('laps recorded', htmlBare(byId(root, 'laps')), '<li>01:02:04 UTC</li><li>01:02:04 UTC</li>');
click('Clear laps');
expect('laps cleared', htmlBare(byId(root, 'laps')), '');
click('Pause');
expect('pausing drops the tick subscription', cleared, 1);
expect('pause button flips', byRole(root, 'button', 'Resume') !== null, true);
click('Resume');
expect('resuming restarts the subscription', intervals.length === 2 && intervals[1].ms === 1000, true);

// --- Notes: a pure page, its transformations reach the DOM through Html.map ---

goTo('Notes');
expect('notes page shows', byId(root, 'notes') !== null, true);
expect('no notes yet', textOf('summary'), ' 0 of 0 shown');
const draft = () => byId(root, 'draft');
draft().listeners.input({ target: { value: '  buy milk  ' } });
draft().listeners.keydown({ key: 'Enter', preventDefault: () => {} });
expect('enter adds the trimmed note', htmlBare(byId(root, 'list')), '<li>buy milk<button>x</button></li>');
expect('draft cleared', draft().attrs.get('value'), '');
draft().listeners.input({ target: { value: '   ' } });
click('Add');
expect('a blank draft adds nothing', textOf('summary'), ' 1 of 1 shown');
draft().listeners.input({ target: { value: 'call mum' } });
click('Add');
draft().listeners.input({ target: { value: 'buy bread' } });
click('Add');
expect('three notes', textOf('summary'), ' 3 of 3 shown');
byId(root, 'search').listeners.input({ target: { value: 'buy' } });
expect('search filters the list', htmlBare(byId(root, 'list')), '<li>buy milk<button>x</button></li><li>buy bread<button>x</button></li>');
expect('summary counts the match', textOf('summary'), ' 2 of 3 shown');
byRoleAll(byId(root, 'list'), 'button', 'x')[0].listeners.click();
expect('delete removes that note only', htmlBare(byId(root, 'list')), '<li>buy bread<button>x</button></li>');
expect('summary after delete', textOf('summary'), ' 1 of 2 shown');
click('Clear all');
expect('clear all empties notes and search', textOf('summary'), ' 0 of 0 shown');

// --- Page state survives navigation ---

goTo('Counter');
expect('counter kept its state while other pages showed', textOf('count'), '5');
expect('current page marked in the nav', byRoleAll(byId(root, 'pages'), 'button', 'Counter')[0].attrs.get('class'), 'current');
expect('other pages not marked', byRoleAll(byId(root, 'pages'), 'button', 'Clock')[0].attrs.get('class') ?? '', '');
