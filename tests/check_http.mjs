// Node harness for http: Http.get crosses as a command, fetch runs
// (mocked), and the outcome arrives in update as a typed
// GotQuote(Try(Response, ...)) msg: Ok carries status/headers/body, Err is
// transport-level (network failure or timeout).
// Run from the repo root: node tests/check_http.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare } from './fakedom.mjs';
import { expect } from './harness.mjs';

const bytes = readFileSync('build/http.wasm');
const tick = () => new Promise((r) => setTimeout(r, 0));

// --- Success path ---
const requests = [];
globalThis.fetch = (url, opts) => {
  requests.push({ url, method: opts.method, headers: opts.headers });
  return Promise.resolve({
    status: 200,
    headers: new Headers({ 'content-type': 'application/json' }),
    arrayBuffer: async () => new TextEncoder().encode('["Never half-ass two things.","Whole-ass one thing."]').buffer,
  });
};

const logged = [];
const realLog = console.log;
console.log = (...a) => logged.push(a.join(' '));
const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
console.log = realLog;

expect('initial state', htmlBare(root).includes('Would you like a Ron Swanson quote?'), true);
expect('no request before the click', requests.length, 0);

console.log = (...a) => logged.push(a.join(' '));
find(root, 'Treat Yo Self').listeners.click();
console.log = realLog;
expect('loading state painted synchronously', find(root, 'Getting a quote...') !== null, true);
expect('request sent', requests.length, 1);
expect('request method', requests[0].method, 'GET');
expect('request url', requests[0].url, 'https://ron-swanson-quotes.herokuapp.com/v2/quotes');
expect('Console.log command from update', logged.includes('Requesting a quote...'), true);

await tick(); await tick(); // let the fetch promise resolve and dispatch
expect('quote decoded from JSON body', htmlBare(root).includes('<pre>Never half-ass two things.\nWhole-ass one thing.</pre>'), true);

// --- Failure path (network error → Err(HttpErr(NetworkError))) ---
globalThis.fetch = () => Promise.reject(new Error('offline'));
const root2 = new El('#root');
console.log = () => {};
await mount({ wasm: bytes, root: root2, flags: '', dom: fakeDom });
find(root2, 'Treat Yo Self').listeners.click();
console.log = realLog;
await tick(); await tick();
expect('error state rendered', htmlBare(root2).includes('Couldn\'t get quote, cause: The request never completed'), true);

// --- In-flight response arriving after unmount must not re-enter wasm ---
// Http.get sends with no timeout, so no abort timer is scheduled; the
// pending fetch just dangles until released below.
let release;
globalThis.fetch = () => new Promise((r) => { release = r; });
const root3 = new El('#root');
console.log = () => {};
const app3 = await mount({ wasm: bytes, root: root3, flags: '', dom: fakeDom });
find(root3, 'Treat Yo Self').listeners.click();
console.log = realLog;
const frozen = htmlBare(root3);
app3.unmount();
release({
  status: 200,
  headers: new Headers({ 'content-type': 'application/json' }),
  arrayBuffer: async () => new TextEncoder().encode('["late"]').buffer,
});
await tick(); await tick();
expect('late response after unmount is a no-op', htmlBare(root3), frozen);

