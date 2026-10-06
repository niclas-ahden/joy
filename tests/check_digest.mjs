// Node harness for the digest paths check_upload.mjs does not reach:
// WebCrypto.digest sends in-memory bytes across the wasm boundary to
// crypto.subtle, digest_file_slice hashes only the requested byte range of a
// browser-held file, a file id the browser does not hold delivers the empty
// hash that renders as failure, and file digests asked for all at once run
// at most navigator.hardwareConcurrency at a time.
// Run from the repo root: node tests/check_digest.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, FakeFile, byId, fakeDom, find, findTag, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('digest'));
const tick = () => new Promise((r) => setTimeout(r, 0));
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
// Digests resolve on the crypto threadpool, so poll for the rendered result
// instead of counting macrotask ticks (a loaded machine needs more of them).
const settled = async (pred) => {
  for (let i = 0; i < 500 && !pred(); i++) await tick();
  return pred();
};

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });

// In-memory bytes, hashed with an algorithm the Roc builtin does not offer.
find(root, 'Hash memory').listeners.click();
expect('hashing state painted synchronously', htmlBare(root).includes('mem: hashing...'), true);
const mem = hex(await crypto.subtle.digest('SHA-384', new TextEncoder().encode('hello joy')));
expect('sha384 over the wasm-sent bytes', await settled(() => htmlBare(root).includes(`mem: ${mem}`)), true);

// A byte range of a picked file: start 2, len 5 of "abcdefghij" is "cdefg".
const input = findTag(root, 'input');
input.fakeFile = new FakeFile('data.bin', 'abcdefghij', 'application/octet-stream');
input.listeners.change({ target: input });
const slice = hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('cdefg')));
expect('sha256 over only the requested range', await settled(() => htmlBare(root).includes(`slice: ${slice}`)), true);

// A file id nothing was registered under fails with the empty hash.
find(root, 'Hash missing').listeners.click();
expect('unknown file id renders as failure', await settled(() => htmlBare(root).includes('missing: failed')), true);

// Six chunk digests asked for at once, with two cores: only two chunks are
// read at a time, and each one hashed lets the next one start, so a huge
// file is never all in memory. The file holds every read until the harness
// lets it go, which makes the reads in flight countable.
Object.defineProperty(globalThis.navigator, 'hardwareConcurrency', { value: 2, configurable: true });
const reads = [];
class HeldFile extends FakeFile {
  slice(start = 0, end = this.size) {
    return new HeldFile(this.name, this.bytes.slice(start, end), this.type);
  }
  arrayBuffer() {
    return new Promise((resolve) => reads.push(() => resolve(this.bytes.slice().buffer)));
  }
}
const chunked = byId(root, 'chunked');
chunked.fakeFile = new HeldFile('chunks.bin', 'abcdefghijkl', 'application/octet-stream');
chunked.listeners.change({ target: chunked });
await tick();
expect('two chunk reads start, not six', reads.length, 2);
for (let hashed = 1; hashed <= 6; hashed++) {
  reads[hashed - 1]();
  const started = Math.min(6, hashed + 2);
  expect(`chunk ${hashed} hashed lets one more read start`, await settled(() => reads.length === started), true);
  expect(`at most two reads in flight after ${hashed} hashed`, reads.length - hashed <= 2, true);
}
const chunkHashes = await Promise.all(
  ['ab', 'cd', 'ef', 'gh', 'ij', 'kl'].map(async (s) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))),
);
expect('every chunk hashed, in order', await settled(() => htmlBare(root).includes(`chunks: ${chunkHashes.join(',')}`)), true);
