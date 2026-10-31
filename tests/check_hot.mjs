// Node harness for hot reload (`app.reload` in www/runtime.js): an app is
// driven through every kind of message source, then reloaded into rebuilt
// modules, each of which must pick up in the state the last one reached by
// replaying the session. tests/apps/hot_v1.roc to hot_v4.roc are four builds
// of that app (tests.roc builds them with JOY_HOT): v2 rearranges the view,
// v3 changes the model, the messages and update, v4 crashes on one message.
// Run from the repo root: JOY_OPT=speed node tests/check_hot.mjs
import { readFileSync } from 'node:fs';
import { mock } from 'node:test';
const { mount } = await import(`../build/${process.env.JOY_OPT}/runtime.js`);
// Joy's dev module, which hot reloads every app mounted after it and gives it
// app.reload, exactly as in a page the dev server serves.
import '../www/hot.js';
import { El, FakeFile, activeGlobalListeners, activeObservers, countTextReads, fakeDom, popstate } from './fakedom.mjs';
import { expect, hotWasmPath, plainWasmPath } from './harness.mjs';

const build = (n) => readFileSync(hotWasmPath(`hot_v${n}`));
// Timers and the clock are node:test's, so a check says how much time passes
// and nothing waits for it. `flush` lets what is already settled run.
mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });
const flush = () => new Promise((resolve) => setImmediate(resolve));

const byId = (node, id) => {
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children ?? []) {
    const hit = byId(c, id);
    if (hit) return hit;
  }
  return null;
};
const textOf = (node) => node.text ?? (node.children ?? []).map(textOf).join('');

const root = new El('#root');
const read = (id) => textOf(byId(root, id));
const click = (id) => byId(root, id).listeners.click();
const type = (s) => byId(root, 'draft').listeners.input({ target: { value: s } });
const items = () => byId(root, 'items').children.map(textOf).join(',');
const removeItem = (name) => byId(root, 'items').children.find((b) => textOf(b) === name).listeners.click();

// Requests stay unanswered until `answer` (or `fail`, the way a network error
// ends one), so one can be left in flight across a reload. `requests` has
// each URL asked for, `sent` each "METHOD url". A response body is the
// `body` for its URL, or names the URL.
const requests = [];
const sent = [];
const unanswered = [];
const body = new Map();
globalThis.fetch = (url, opts) => {
  requests.push(url);
  sent.push(`${opts?.method ?? 'GET'} ${url}`);
  return new Promise((resolve, reject) => unanswered.push({
    respond: () => resolve({
      status: 200,
      headers: new Headers(),
      arrayBuffer: async () => (body.get(url) ?? new TextEncoder().encode(`quote from ${url}`)).buffer,
    }),
    fail: () => reject(new TypeError('Failed to fetch')),
  }));
};
const answer = async () => {
  for (const request of unanswered.splice(0)) request.respond();
  await flush();
};
const fail = async () => {
  for (const request of unanswered.splice(0)) request.fail();
  await flush();
};
const sentTo = (line) => sent.filter((s) => s === line).length;

// --- v1: one message from every kind of source ---
const app = await mount({ wasm: build(1), root, flags: '', dom: fakeDom });
click('inc'); click('inc'); click('inc'); click('dec');
type('apple'); click('add');
type('pear'); click('add');
type('plum'); click('add');
removeItem('pear');
click('fetch');
await answer();
click('later');
mock.timers.tick(5);
await flush();
app.sendPort('ping', 'hello');
// Left in flight across the reload: v1 must never see the answer, and v2
// must send the request again once live, since its replay asked for it.
click('fetch');

expect('v1 state', [read('count'), items(), read('quote'), read('fired'), read('pinged')].join('|'),
  '2|apple,plum|loading|1|hello');

// --- v2: the same app with every handler moved ---
const r2 = await app.reload(build(2));
expect('v2 replayed every message', r2.replayed, 17);
expect('v2 skipped none', r2.skipped.length, 0);
expect('v2 did not restart', r2.restarted, false);
expect('v2 view is the new one', textOf(root).startsWith('Version 2'), true);
expect('v2 kept the state', [read('count'), items(), read('quote'), read('fired'), read('pinged')].join('|'),
  '2|plum,apple|loading|1|hello');
// The request v1 left in flight is v2's now, not sent a second time.
expect('v2 took over the request left in flight, sending nothing', requests.length, 2);
expect('v2 reports the request it took over', `${r2.handedOver}|${r2.ignored.length}|${r2.unsent.length}`, '1|0|0');
expect('v2 root holds only the new view', root.children.length, 1);
expect('v2 freed what the replay dropped', app.instance.exports.dealloc_miss(), 0);

await answer();
expect('v2 got the answer', read('quote'), 'quote from /quote');

click('inc');
type('fig'); click('add');
app.sendPort('ping', 'again');
expect('v2 runs on after the reload', [read('count'), items(), read('pinged')].join('|'), '3|fig,plum,apple|again');

// --- v3: new model, update and messages ---
// Decrement is gone, so this replay is told to skip it (the default stops
// there, see the end of this file).
const r3 = await app.reload(build(3), { replay: 'skip' });
expect('v3 skipped the message it no longer has', r3.skipped.join(','), 'Decrement');
expect('v3 did not stop', r3.stopped, null);
// v1's 17 and v2's own 5: the answer to the request it sent again, an
// increment, typing fig, adding it and a ping.
expect('v3 replayed the rest', r3.replayed, 21);
// Four increments, now worth ten each, and four adds in the new field.
expect('v3 redid the session with its own update', [read('count'), read('added'), items(), read('quote')].join('|'),
  '40|4|apple,plum,fig|quote from /quote');
expect('v3 freed what the replay dropped', app.instance.exports.dealloc_miss(), 0);

// --- v4: crashes on Remove, which the session holds ---
const r4 = await app.reload(build(4));
expect('v4 reports the crash', r4.crashed?.message.includes('Remove'), true);
// Replayed up to the message that crashed it: pear is still there, and what
// came after (the fetch, the timers, the pings) never happened.
expect('v4 stopped short of the crash', [read('count'), read('added'), items(), read('quote'), read('fired')].join('|'),
  '30|3|apple,pear,plum||0');

let threw = false;
try {
  removeItem('pear');
} catch {
  threw = true;
}
expect('v4 crashes for real too', threw, true);

// The fix arrives as another reload, into the crashed app's state.
const r5 = await app.reload(build(3));
expect('fixed build picks up where the crash left off', [read('count'), items()].join('|'), '30|apple,pear,plum');
expect('fixed build skipped nothing', r5.skipped.length + (r5.crashed ? 1 : 0), 0);
removeItem('pear');
expect('fixed build removes', items(), 'apple,plum');

app.unmount();

// --- By default a replay stops at the first message it cannot run ---
const stopRoot = new El('#stop');
const stopCount = () => textOf(byId(stopRoot, 'count'));
const stopApp = await mount({ wasm: build(1), root: stopRoot, flags: '', dom: fakeDom });
for (const button of ['inc', 'dec', 'inc', 'inc']) byId(stopRoot, button).listeners.click();
const rs = await stopApp.reload(build(3));
expect('default stops at the first message that is gone', `${rs.stopped?.text}|${rs.stopped?.reason}|${rs.stopped?.dropped}`, 'Decrement|gone|3');
// Only the first increment, now worth ten, came before it.
expect('default leaves the state from just before it', `${stopCount()}|${rs.replayed}|${rs.skipped.length}`, '10|1|0');
const badPolicy = await stopApp.reload(build(3), { replay: 'later' }).then(() => 'resolved', (err) => err.name);
expect('an unknown policy is refused', badPolicy, 'TypeError');
stopApp.unmount();

// --- A build without JOY_HOT records nothing, so a reload restarts ---
const counter = readFileSync(plainWasmPath('counter'));
const plainRoot = new El('#plain');
const plain = await mount({ wasm: counter, root: plainRoot, flags: '', dom: fakeDom });
byId(plainRoot, 'increment').listeners.click();
const rp = await plain.reload(counter);
expect('a build without hot reload restarts', rp.restarted, true);
expect('and starts over', textOf(plainRoot), '+0-');
plain.unmount();

// --- Messages Str.inspect cannot print in full ---
// Every Apply reads `Apply(<function>)` and every Choose `Choose(<opaque>)`
// (tests/apps/hot_fn_v1.roc), so the replay picks among the buttons that
// produce such a text by the id and text of the one that was clicked, and
// stops where that cannot single one out.
const fnBuild = (n) => readFileSync(hotWasmPath(`hot_fn_v${n}`));
const fnRoot = new El('#fn');
const fnRead = (id) => textOf(byId(fnRoot, id));
const fnApp = await mount({ wasm: fnBuild(1), root: fnRoot, flags: '', dom: fakeDom });
byId(fnRoot, 'plus').listeners.click();
byId(fnRoot, 'times').listeners.click();
byId(fnRoot, 'mint').listeners.click();
expect('fn v1 state', `${fnRead('count')}|${fnRead('flavor')}`, '20|mint');

// v2 swaps each pair, so the first button to match would be the wrong one.
const f2 = await fnApp.reload(fnBuild(2));
expect('fn v2 told the swapped buttons apart by id', `${fnRead('count')}|${fnRead('flavor')}`, '20|mint');
expect('fn v2 replayed all three', f2.replayed, 3);
expect('fn v2 did not stop', f2.stopped, null);
expect('fn v2 freed every probed message', fnApp.instance.exports.dealloc_miss(), 0);

// The twins differ only in their function: same id (none), same text.
byId(fnRoot, 'twins').children[0].listeners.click();
expect('fn v2 ran the first twin', fnRead('count'), '19');
const f1 = await fnApp.reload(fnBuild(1));
expect('fn twin stops the replay', `${f1.stopped?.text}|${f1.stopped?.reason}`, 'Apply(<function>)|ambiguous');
expect('fn stop leaves out the twin alone', f1.stopped?.dropped, 1);
expect('fn state is from just before the twin', `${fnRead('count')}|${fnRead('flavor')}`, '20|mint');

// What a stopped replay kept is all that is left to replay.
const f1again = await fnApp.reload(fnBuild(1));
expect('fn kept session replays without stopping', `${f1again.replayed}|${f1again.stopped}`, '3|null');
fnApp.unmount();

// Told to skip, the same twin is left out and the replay goes on past it.
const skipRoot = new El('#skip');
const skipApp = await mount({ wasm: fnBuild(1), root: skipRoot, flags: '', dom: fakeDom });
byId(skipRoot, 'plus').listeners.click();
byId(skipRoot, 'twins').children[0].listeners.click();
byId(skipRoot, 'times').listeners.click();
const fs2 = await skipApp.reload(fnBuild(2), { replay: 'skip' });
// +1, the twin left out, then x10: (1 + 1) * 10.
expect('fn skip leaves out the twin and goes on', `${textOf(byId(skipRoot, 'count'))}|${fs2.skipped.join(',')}|${fs2.stopped}`, '20|Apply(<function>)|null');
skipApp.unmount();

// An element's text is read only for a message whose text is ambiguous, the
// one case a replay tells sources apart by it: reading it walks the subtree.
const textReads = countTextReads();
const readsRoot = new El('#reads');
const readsApp = await mount({ wasm: build(1), root: readsRoot, flags: '', dom: fakeDom });
for (let i = 0; i < 3; i++) byId(readsRoot, 'inc').listeners.click();
expect('plain messages read no element text', textReads.reads, 0);
readsApp.unmount();
const fnReadsRoot = new El('#fn-reads');
const fnReadsApp = await mount({ wasm: fnBuild(1), root: fnReadsRoot, flags: '', dom: fakeDom });
byId(fnReadsRoot, 'plus').listeners.click();
byId(fnReadsRoot, 'mint').listeners.click();
expect('each ambiguous message reads its element once', textReads.reads, 2);
fnReadsApp.unmount();

// --- A request in flight when the replay stops before the message that sent it ---
// The rebuilt app is left in a state from before the request existed, so the
// answer must never reach it, and nothing may be sent again: the request
// already reached the server once. Stopped first at a message that is gone,
// then at one that is ambiguous.
await answer(); // nothing from the checks above still pending
const goneRoot = new El('#in-flight-gone');
const goneRead = (id) => textOf(byId(goneRoot, id));
const goneApp = await mount({ wasm: build(1), root: goneRoot, flags: '', dom: fakeDom });
byId(goneRoot, 'inc').listeners.click();
byId(goneRoot, 'dec').listeners.click();
byId(goneRoot, 'fetch').listeners.click();
const sentByGone = requests.length;
const rg = await goneApp.reload(build(3));
// Only the increment, now worth ten, came before Decrement, and Fetch after.
expect('in flight past a gone stop: the replay stopped before the request', `${rg.stopped?.text}|${goneRead('count')}|${goneRead('quote')}`, 'Decrement|10|');
expect('in flight past a gone stop: nothing is sent again', requests.length, sentByGone);
expect('in flight past a gone stop: reported as ignored', rg.ignored.join(','), 'GET /quote');
await answer();
expect('in flight past a gone stop: the answer never reaches the app', goneRead('quote'), '');
goneApp.unmount();

const ambiguousRoot = new El('#in-flight-ambiguous');
const ambiguousRead = (id) => textOf(byId(ambiguousRoot, id));
const ambiguousApp = await mount({ wasm: fnBuild(1), root: ambiguousRoot, flags: '', dom: fakeDom });
byId(ambiguousRoot, 'twins').children[0].listeners.click();
byId(ambiguousRoot, 'fetch').listeners.click();
const sentByAmbiguous = requests.length;
const ra = await ambiguousApp.reload(fnBuild(2));
// The twin was the first message, so the app is back where init left it.
expect('in flight past an ambiguous stop: the replay stopped before the request', `${ra.stopped?.reason}|${ambiguousRead('count')}|${ambiguousRead('quote')}`, 'ambiguous|1|');
expect('in flight past an ambiguous stop: nothing is sent again', requests.length, sentByAmbiguous);
expect('in flight past an ambiguous stop: reported as ignored', ra.ignored.join(','), 'GET /quote');
await answer();
expect('in flight past an ambiguous stop: the answer never reaches the app', ambiguousRead('quote'), '');
ambiguousApp.unmount();

// --- Every other kind of source ---
// tests/apps/hot_src_v1.roc gets a message from each kind of source the app
// above has not got one from, and hot_src_v2.roc has three of them no longer
// hear what they heard: those messages are gone, even though the source
// would still produce them if handed the recorded input.
const srcBuild = (n) => readFileSync(hotWasmPath(`hot_src_v${n}`));
const srcRoot = new El('#sources');
const srcLog = () => textOf(byId(srcRoot, 'log'));
const srcApp = await mount({ wasm: srcBuild(1), root: srcRoot, flags: '', dom: fakeDom });
byId(srcRoot, 'field').listeners.keydown({ key: 'Enter', code: 'Enter' });
byId(srcRoot, 'pad').listeners.pointerdown({ clientX: 12 });
const upload = byId(srcRoot, 'upload');
upload.fakeFile = new FakeFile('notes.txt', 'hi');
upload.listeners.change({ target: upload });
activeObservers().find((o) => o.node === byId(srcRoot, 'sentinel')).fire();
mock.timers.tick(1000);
await flush();
for (const l of activeGlobalListeners()) l.fn({ key: 'Escape', code: 'Escape', preventDefault: () => {} });
srcApp.sendPort('ping', 'hi');
popstate('/next');
const srcAll = 'key Enter,pointer 12,file notes.txt,seen,tick,escape Escape,ping hi,url /next';
expect('sources: each delivered', srcLog(), srcAll);
const src1 = await srcApp.reload(srcBuild(1));
expect('sources: each replays from its own source', `${src1.replayed}|${src1.stopped}|${srcLog()}`, `8|null|${srcAll}`);
const src2 = await srcApp.reload(srcBuild(2), { replay: 'skip' });
expect('sources: what a source no longer hears is gone', src2.skipped.join(','), 'Key("Enter"),Escaped("Escape"),Pinged("hi")');
expect('sources: the rest replays', srcLog(), 'pointer 12,file notes.txt,seen,tick,url /next');
srcApp.unmount();

mock.timers.reset();
