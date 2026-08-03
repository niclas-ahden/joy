// Node harness for infinite_scroll: the sentinel's visibility observer
// reveals batches, the rearm key recreates the observer per batch, and
// loading stops at max_items.
// Run from the repo root: node tests/check_infinite_scroll.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, htmlBare, activeObservers } from './fakedom.mjs';
import { expect } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync('build/infinite_scroll.wasm'), root, flags: '', dom: fakeDom });
const itemCount = () => (htmlBare(root).match(/Item \d+/g) ?? []).length;

expect('first batch rendered', itemCount(), 20);
expect('last item of the batch', htmlBare(root).includes('Item 20'), true);
expect('sentinel says loading', find(root, 'Loading more...') !== null, true);
expect('one active observer', activeObservers().length, 1);
expect('observer margin', activeObservers()[0].rootMargin, '200px');

// The sentinel comes into view: next batch, observer re-armed (recreated).
activeObservers()[0].fire();
expect('second batch rendered', itemCount(), 40);
expect('still one active observer', activeObservers().length, 1);

// Keep scrolling to the end.
activeObservers()[0].fire();
activeObservers()[0].fire();
activeObservers()[0].fire();
expect('all items rendered', itemCount(), 100);
expect('sentinel says done', find(root, 'No more items') !== null, true);

// At max_items update returns none: no re-render, so the observer is not
// re-armed and further firings change nothing.
const sentinelObserver = activeObservers()[0];
sentinelObserver.fire();
expect('loading stopped cleanly', itemCount(), 100);
expect('observer not re-armed after none', activeObservers()[0] === sentinelObserver, true);

