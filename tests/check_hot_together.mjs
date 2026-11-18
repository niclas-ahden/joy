// Node harness for what a hot reload replays with the render held (see
// catchUp in www/hot.js):
//
// - Handlers that one event passed ran together, each with the message it
//   had in the view the event happened in, so they replay together too. Run
//   one at a time, the second would find no handler with its message.
// - A message that arrived while another was in progress, like a port's
//   answer sent from inside the handler that asked, is recorded when its
//   turn comes.
// - Messages that come in through a subscription or an answer need no view,
//   so a session of clock ticks renders once on its way back.
//
// tests.roc builds tests/apps/rows.roc and port_answer.roc with JOY_HOT.
// Run from the repo root: JOY_OPT=speed node tests/check_hot_together.mjs
import { readFileSync } from 'node:fs';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
import '../www/hot.js';
import { El, byId, fakeDom } from './fakedom.mjs';
import { countingDom, expect, hotWasmPath } from './harness.mjs';

// The clock ticks when a check says so.
const intervals = [];
globalThis.setInterval = (fn) => { intervals.push(fn); return intervals.length; };
globalThis.clearInterval = () => {};
const tick = () => intervals.at(-1)();

const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

// --- Handlers one event passed ---

const rows = readFileSync(hotWasmPath('rows'));
const root = new El('#root');
const counted = countingDom();
const app = await mount({ wasm: rows, root, flags: '', dom: counted.dom });
const read = (id) => textOf(byId(root, id));
const listed = (list) => byId(root, list).children.map((li) => li.attrs.get('id')).join(',');
const click = (...ids) => {
  const ev = { bubbles: true, stopped: false, stopPropagation() { this.stopped = true; } };
  for (const node of ids.map((id) => byId(root, id))) {
    if (ev.stopped) break;
    node.listeners.click?.(ev);
  }
};

click('plain-del-beta', 'plain-beta');
click('keyed-del-delta', 'keyed-delta');
click('flip', 'outer');
click('plain-alpha');
const before = [read('log'), listed('plain'), listed('keyed')].join('|');
expect('the session as it was lived', before,
  'deleted beta, selected beta, deleted delta, selected delta, flipped, saw plain, selected alpha|plain-alpha,plain-gamma,plain-delta|keyed-alpha,keyed-beta,keyed-gamma');

const again = await app.reload(rows);
expect('every message replayed', `${again.replayed}|${again.skipped.length}|${again.stopped ?? 'ran to the end'}`, '7|0|ran to the end');
expect('the replay ends where the session was', [read('log'), listed('plain'), listed('keyed')].join('|'), before);
click('plain-del-gamma', 'plain-gamma');
expect('and the app goes on', read('log').endsWith('deleted gamma, selected gamma'), true);

// Two such events in a row: the second happened in the view the first left.
click('flip', 'outer');
click('flip', 'outer');
const flipped = read('log');
expect('each click was heard by the view it happened in', flipped.endsWith('flipped, saw flipped, flipped, saw plain'), true);
const twice = await app.reload(rows);
expect('one event after another replays, each from its own view', `${twice.skipped.length}|${twice.stopped ?? 'ran to the end'}|${read('log')}`, `0|ran to the end|${flipped}`);

// --- A session of ticks renders once ---

for (let i = 0; i < 300; i++) tick();
expect('the clock ticked', read('ticks'), '300');
const writes = counted.counts.textWrites;
const ticked = await app.reload(rows);
expect('the ticks replayed', `${ticked.replayed}|${read('ticks')}`, '313|300');
// A render per tick would write the count 300 times into the view the
// replay builds.
expect('with the view written a few times, not once per tick', counted.counts.textWrites - writes < 20, true);

// --- An answer that waited for the message that asked ---

const answering = readFileSync(hotWasmPath('port_answer'));
const page = new El('#page');
const asker = await mount({
  wasm: answering,
  root: page,
  flags: '',
  dom: fakeDom,
  setup: (a) => a.onPort('ask', () => a.sendPort('answer', '')),
});
asker.sendPort('x', 'one');
asker.sendPort('go', '');
asker.sendPort('y', 'two');
expect('the question was answered', textOf(page), 'phase 2 log x:one y:two');
const asked = await asker.reload(answering);
expect('the answer is in the session', `${asked.replayed}|${asked.skipped.length}`, '4|0');
expect('and the replay ends where the session was', textOf(page), 'phase 2 log x:one y:two');
