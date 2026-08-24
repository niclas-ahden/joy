// Node harness for the digest paths check_upload.mjs does not reach:
// WebCrypto.digest sends in-memory bytes across the wasm boundary to
// crypto.subtle, digest_file_slice hashes only the requested byte range of a
// browser-held file, and a file id the browser does not hold delivers the
// empty hash that renders as failure.
// Run from the repo root: node tests/check_digest.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, FakeFile, fakeDom, find, findTag, htmlBare } from './fakedom.mjs';
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
