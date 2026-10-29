// HTTP for the platform's Http module: a request with a body the app
// sends, or with a byte range of a browser-held file the browser streams,
// whose bytes never enter the app.
//
// The answer is the status, the headers and the body. Status 0 is a request
// that never completed and 1 one that timed out, which the platform turns
// into errors (real statuses start at 100), so a 4xx or 5xx answer is a
// response like any other.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// helper fetch_http
function readRequest(args) {
  const method = args.str();
  const url = args.str();
  const headers = {};
  for (let n = args.u32(); n > 0; n--) headers[args.str()] = args.str();
  return { method, url, headers };
}

function answer(status, headers, body) {
  const w = new WireWriter().u16(status).u32(headers.length);
  for (const [name, value] of headers) w.str(name).str(value);
  return w.bytes(body);
}

// A timeout aborts the request and answers status 1, any other network or
// body failure answers 0.
function fetchHttp({ method, url, headers }, body, timeoutMs) {
  const opts = { method, headers };
  if (body !== null) opts.body = body;
  let timer = null;
  let timedOut = false;
  if (timeoutMs > 0) {
    const controller = new AbortController();
    opts.signal = controller.signal;
    timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
  }
  return fetch(url, opts)
    .then(async (resp) => {
      const body = new Uint8Array(await resp.arrayBuffer());
      const respHeaders = resp.headers?.entries ? [...resp.headers.entries()] : [];
      return answer(resp.status, respHeaders, body);
    })
    .catch(() => answer(timedOut ? 1 : 0, [], new Uint8Array()))
    .finally(() => clearTimeout(timer));
}

//// op joy/http/send needs fetch_http
defineOperation('joy/http/send', (args) => {
  const request = readRequest(args);
  const body = args.bytes();
  return fetchHttp(request, body.length > 0 ? body : null, args.u64());
});

//// op joy/http/send_file needs fetch_http
defineOperation('joy/http/send_file', (args, host) => {
  const request = readRequest(args);
  const fileId = args.u32();
  const start = args.u64();
  const len = args.u64();
  const timeoutMs = args.u64();
  const file = host.file(fileId);
  if (!file) return answer(0, [], new Uint8Array()); // an unknown file never completes
  const slice = len > 0 ? file.slice(start, start + len) : start > 0 ? file.slice(start) : file;
  return fetchHttp(request, slice, timeoutMs);
});
