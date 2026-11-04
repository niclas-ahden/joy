// Node harness for the dev client's event stream (www/hot.js): a page a browser
// keeps for Back and Forward must not keep its stream, since a browser opens 6
// connections to a port and a few clicks would use them up.
// Run from the repo root: node tests/check_hot_events.mjs
import assert from 'node:assert/strict';

const streams = [];
class FakeEventSource {
  constructor(url) {
    this.url = url;
    this.closed = false;
    streams.push(this);
  }
  addEventListener() {}
  close() {
    this.closed = true;
  }
}

const pageListeners = {};
globalThis.document = {};
globalThis.location = { protocol: 'http:', hostname: 'portal.localhost', href: 'http://portal.localhost/' };
globalThis.EventSource = FakeEventSource;
globalThis.JOY_DEV_PORT = 8123;
globalThis.addEventListener = (name, listener) => {
  pageListeners[name] = listener;
};
globalThis.fetch = async () => ({ headers: { get: () => 'no-cache' } });

await import('../www/hot.js');

assert.equal(streams.length, 1, 'a page opens one stream');
assert.equal(streams[0].url, 'http://portal.localhost:8123/.joy/events', 'the stream is on the events port');
assert.equal(streams[0].closed, false, 'the stream stays open while the page is shown');

pageListeners.pagehide({ persisted: true });
assert.equal(streams[0].closed, true, 'a page that is left closes its stream');

pageListeners.pageshow({ persisted: false });
assert.equal(streams.length, 1, 'a page that just loaded has its stream already');

pageListeners.pageshow({ persisted: true });
assert.equal(streams.length, 2, 'a page that comes back opens a new stream');
assert.equal(streams[1].closed, false, 'the new stream is open');

pageListeners.pagehide({ persisted: true });
assert.equal(streams[1].closed, true, 'leaving again closes the new stream');

console.log('hot events checks passed');
