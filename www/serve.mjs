// Dev server for the examples, started and torn down by watch.roc and e2e.roc.
//
// It exposes a deliberately tiny URL space so that www/index.html can stay the
// plainest page possible: the app is always ./app.wasm, the runtime is always
// ./runtime.js, and there are no query strings, no injected globals and no
// repo paths. That page is what someone copies into their own project, so it
// must not know anything about this repo's layout. Everything that has to know
// lives here instead.
//
// Two modes:
//
//   node www/serve.mjs 8000 counter
//     One app pinned at `/`, which is what watch.roc starts. The site looks
//     like it has a single app on it, because as far as the page knows it does.
//
//   node www/serve.mjs 8787
//     Every app under its own prefix, `/counter/` and `/modal/`, which is what
//     e2e.roc starts so several tests can share one server. Relative paths do
//     the routing, so the page served there is byte for byte the same one.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const port = Number(process.argv[2] ?? 8000);
const pinned = process.argv[3] ?? null;
const rootDir = process.cwd();

// Nothing a watch loop serves is cacheable. Browsers cache heuristically when
// no cache headers are present, and a stale wasm survives even a hard reload,
// because runtime.js fetches it rather than the browser loading it.
const headers = (type) => ({ 'content-type': type, 'cache-control': 'no-store' });

// App names come from the URL in prefix mode and reach a file path below, so
// they are checked against what build.roc can actually produce. That, plus a
// route table of literals, means no request can name a file of its own.
const isAppName = (app) => /^[a-z0-9_]+$/i.test(app);

// The whole URL space, relative to an app's root.
function routeFor(app, rest) {
  switch (rest) {
    case '/':
      return { file: 'www/index.html', type: 'text/html' };
    case '/runtime.js':
      return { file: 'www/runtime.js', type: 'text/javascript' };
    // Not referenced by the page. The frame-time meter, loaded by hand from
    // the devtools console.
    case '/perf.js':
      return { file: 'www/perf.js', type: 'text/javascript' };
    case '/app.wasm':
      return { file: `build/${app}.wasm`, type: 'application/wasm' };
    default:
      return null;
  }
}

// Split a request path into the app it belongs to and the path within that
// app. Pinned mode has no prefix to strip, everything sits at the root.
function resolve(pathname) {
  if (pinned) return { app: pinned, rest: pathname };
  if (pathname === '/') return {};
  const at = pathname.indexOf('/', 1);
  // `/counter` names an app but no path within it, so the page's own
  // `./runtime.js` would resolve to `/runtime.js` and miss. The trailing
  // slash is load-bearing, so hand the browser the correct URL.
  if (at < 0) return { redirect: `${pathname}/` };
  return { app: pathname.slice(1, at), rest: pathname.slice(at) };
}

http
  .createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');

    // What tests/apps/fetch.roc requests, shaped like the JSON array the API
    // in examples/http.roc answers with. Absolute, so it lands here in both
    // modes. The app's other button asks for /missing/quote, which no route
    // claims and the 404 below answers, so both branches are reachable.
    if (req.method === 'GET' && url.pathname === '/quote') {
      res.writeHead(200, headers('application/json'));
      res.end(JSON.stringify(['A real fetch, answered by the dev server.']));
      return;
    }

    // The one non-file route: the upload example streams its picked file to
    // POST /upload (an absolute path, so it lands here in both modes). The
    // body is drained and dropped, the example only shows the status. Without
    // this the demo dead-ends in a 404, and a POST must never hit the
    // redirect below, which would turn it into a GET for index.html.
    if (req.method === 'POST' && url.pathname === '/upload') {
      req.resume();
      req.on('end', () => {
        res.writeHead(200, headers('text/plain'));
        res.end('ok');
      });
      return;
    }

    const { app, rest, redirect } = resolve(decodeURIComponent(url.pathname));

    if (redirect) {
      res.writeHead(301, { location: redirect });
      res.end();
      return;
    }

    const route = app && isAppName(app) ? routeFor(app, rest) : null;
    if (!route) {
      res.writeHead(404, headers('text/plain'));
      res.end('not found');
      return;
    }

    try {
      const body = await readFile(path.join(rootDir, route.file));
      res.writeHead(200, headers(route.type));
      res.end(body);
    } catch {
      res.writeHead(404, headers('text/plain'));
      res.end('not found');
    }
  })
  .listen(port, '127.0.0.1');
