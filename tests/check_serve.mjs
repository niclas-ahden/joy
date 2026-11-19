// Node harness for the dev server: the URL space, the redirect that repairs
// a missing trailing slash, the no-store headers a watch loop needs, and the
// app-name guard that keeps a request from naming a file of its own. The
// server runs as a real child process and is driven over HTTP, one process
// per mode and one more pinned to an app with server-rendered pages.
// Run from the repo root: node tests/check_serve.mjs
import { spawn } from 'node:child_process';
import http from 'node:http';
import { expect, optLevel } from './harness.mjs';

// Pid-derived ports keep concurrent harness runs from colliding.
const prefixPort = 8900 + (process.pid % 400);
const pinnedPort = prefixPort + 400;
const pagesPort = prefixPort + 800;

const opt = optLevel();
const servers = [
  spawn('node', ['www/serve.mjs', String(prefixPort), opt]),
  spawn('node', ['www/serve.mjs', String(pinnedPort), opt, 'counter']),
  spawn('node', ['www/serve.mjs', String(pagesPort), opt, 'hydrate_lab']),
];
process.on('exit', () => { for (const s of servers) s.kill(); });

// The server prints nothing, so readiness is a successful connect.
async function ready(port) {
  for (let i = 0; i < 100; i++) {
    try {
      await fetch(`http://127.0.0.1:${port}/`);
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 50));
    }
  }
  throw new Error(`server on ${port} never came up`);
}
await Promise.all([ready(prefixPort), ready(pinnedPort), ready(pagesPort)]);

const get = (port, path) => fetch(`http://127.0.0.1:${port}${path}`, { redirect: 'manual' });

// Prefix mode: every app under its own prefix, nothing at the root.
let res = await get(prefixPort, '/');
expect('prefix mode has no root app', res.status, 404);

// `/counter` misses the trailing slash the page's relative paths need, so
// the browser is handed the correct URL instead of a broken page.
res = await get(prefixPort, '/counter');
expect('missing slash redirects', res.status, 301);
expect('redirect adds the slash', res.headers.get('location'), '/counter/');

res = await get(prefixPort, '/counter/');
expect('app page served', res.status, 200);
expect('page content type', res.headers.get('content-type'), 'text/html');
expect('watch loops need no-store', res.headers.get('cache-control'), 'no-store');
expect('the page is the plain shell', (await res.text()).includes('./runtime.js'), true);

// An app whose build rendered its page gets that page in place of the shell.
// Every other app keeps the shell, and none has styles of its own.
res = await get(prefixPort, '/hydrate_lab/');
expect('server-rendered page served', res.status, 200);
expect('server-rendered page is its own', (await res.text()).includes('<title>Joy hydration lab</title>'), true);
expect('apps without styles 404 them', (await get(prefixPort, '/counter/style.css')).status, 404);

res = await get(prefixPort, '/counter/runtime.js');
expect('runtime served per app', res.status, 200);
expect('runtime content type', res.headers.get('content-type'), 'text/javascript');

res = await get(prefixPort, '/counter/app.wasm');
expect('wasm served per app', res.status, 200);
expect('wasm content type', res.headers.get('content-type'), 'application/wasm');
expect('wasm is wasm', new Uint8Array(await res.arrayBuffer()).slice(0, 4).join(','), '0,97,115,109');

// Only the four routes exist, so no request can name a file of its own.
expect('unknown path within an app 404s', (await get(prefixPort, '/counter/host.rs')).status, 404);
expect('app that was never built 404s', (await get(prefixPort, '/nonexistent_app/app.wasm')).status, 404);

// A URL per page: an app whose build rendered several pages gets each by
// its name, a one-segment path under the app. An app on the shared shell has
// no such pages, and neither has a prefix that names no app, which is what
// the fetch fixture's /missing/quote relies on.
res = await get(prefixPort, '/hydrate_lab/bare');
expect('page url serves the rendered page', res.status, 200);
expect('page url content type', res.headers.get('content-type'), 'text/html');
expect('page url is its own page', await res.text() !== await (await get(prefixPort, '/hydrate_lab/')).text(), true);
expect('a page that was not rendered 404s', (await get(prefixPort, '/hydrate_lab/nope')).status, 404);
expect('deeper page paths 404', (await get(prefixPort, '/hydrate_lab/bare/laps')).status, 404);
expect('page paths with an extension 404', (await get(prefixPort, '/hydrate_lab/bare.html')).status, 404);
expect('apps on the shared shell have no page urls', (await get(prefixPort, '/counter/clock')).status, 404);
expect('unknown prefixes have no page urls', (await get(prefixPort, '/missing/quote')).status, 404);

// The app-name guard: dots and slashes never reach the file path, encoded
// or not. fetch normalizes dot segments before sending, so these go over a
// raw request and the server sees the literal path. A redirect is fine as
// long as its target dead-ends too.
const rawGet = (port, path) =>
  new Promise((resolve, reject) => {
    http
      .request({ host: '127.0.0.1', port, path }, (r) => {
        r.resume();
        r.on('end', () => resolve(r));
      })
      .on('error', reject)
      .end();
  });
async function refused(path) {
  let r = await rawGet(prefixPort, path);
  if (r.statusCode === 301) r = await rawGet(prefixPort, r.headers.location);
  return r.statusCode;
}
expect('dotted app name refused', (await get(prefixPort, '/co.unter/')).status, 404);
expect('traversal refused', await refused('/../../etc/passwd'), 404);
expect('encoded traversal refused', await refused('/%2e%2e/%2e%2e/etc/passwd'), 404);
expect('encoded slash traversal refused', await refused('/..%2f..%2fetc%2fpasswd'), 404);
expect('traversal within an app refused', await refused('/counter/..%2f..%2fflake.nix'), 404);
expect('normalized traversal within an app refused', await refused('/counter/%2e%2e/%2e%2e/flake.nix'), 404);

// Pinned mode: one app at the root, which is what watch.roc serves.
res = await get(pinnedPort, '/');
expect('pinned app at the root', res.status, 200);
expect('pinned page content type', res.headers.get('content-type'), 'text/html');

res = await get(pinnedPort, '/app.wasm');
expect('pinned wasm at the root', res.status, 200);
expect('pinned wasm content type', res.headers.get('content-type'), 'application/wasm');

expect('pinned runtime at the root', (await get(pinnedPort, '/runtime.js')).status, 200);
expect('pinned mode 404s the rest', (await get(pinnedPort, '/secrets')).status, 404);

// The pinned app also answers under its own prefix, so URLs that name the
// app work against this server and the prefix-mode one alike.
expect('pinned app under its own prefix', (await get(pinnedPort, '/counter/')).status, 200);
expect('pinned wasm under its own prefix', (await get(pinnedPort, '/counter/app.wasm')).status, 200);
expect('other prefixes still 404', (await get(pinnedPort, '/modal/')).status, 404);

// Pinned with page urls, which is how watch.roc serves an app with
// server-rendered pages.
expect('pinned page url serves the rendered page', (await get(pagesPort, '/bare')).status, 200);
expect('pinned page url under its own prefix', (await get(pagesPort, '/hydrate_lab/bare')).status, 200);
expect('pinned deeper page paths 404', (await get(pagesPort, '/bare/laps')).status, 404);

for (const s of servers) s.kill();
