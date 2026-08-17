// Node harness for upload: a file input's on_file delivers a typed FileInfo,
// WebCrypto.digest_file hashes the browser-held file (bytes never enter
// wasm; verified against node's own webcrypto), and Http.post_file streams
// the File object as the request body with headers intact.
// Run from the repo root: node tests/check_upload.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, FakeFile, fakeDom, find, findTag, htmlBare } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('upload'));
const tick = () => new Promise((r) => setTimeout(r, 0));
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

const requests = [];
globalThis.fetch = (url, opts) => {
  requests.push({ url, ...opts });
  return Promise.resolve({ status: 201, arrayBuffer: async () => new ArrayBuffer(0) });
};

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const input = findTag(root, 'input');

// Firing change without a file (the user cleared the picker) is not a pick.
input.fakeFile = null;
input.listeners.change({ target: input });
expect('clearing the input is not a pick', htmlBare(root).includes('no file yet'), true);

// Pick a file: the typed FileInfo lands in the model, and the hash command
// runs against the SAME bytes node's webcrypto sees.
const file = new FakeFile('notes.txt', 'hello joy', 'text/plain');
input.fakeFile = file;
input.listeners.change({ target: input });
expect('file metadata delivered', htmlBare(root).includes('picked: notes.txt (9 bytes, text/plain)'), true);
expect('hashing state painted synchronously', htmlBare(root).includes('sha256: hashing...'), true);

await tick(); await tick(); await tick(); // arrayBuffer + digest + dispatch
const expected = hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('hello joy')));
expect('sha256 over the browser-held bytes', htmlBare(root).includes(`sha256: ${expected}`), true);

// Upload: the File object itself is the request body (streamed, not copied
// through wasm), headers ride along, and the response status comes back.
find(root, 'Upload').listeners.click();
expect('request sent', requests.length, 1);
expect('method', requests[0].method, 'POST');
expect('url', requests[0].url, '/upload');
expect('file name header', requests[0].headers['x-file-name'], 'notes.txt');
expect('the File object is the body', requests[0].body === file, true);
await tick(); await tick();
expect('upload status delivered', htmlBare(root).includes('upload status 201'), true);

// Picking a second file re-hashes: ids stay distinct.
const file2 = new FakeFile('other.bin', new Uint8Array([1, 2, 3]), 'application/octet-stream');
input.fakeFile = file2;
input.listeners.change({ target: input });
await tick(); await tick(); await tick();
const expected2 = hex(await crypto.subtle.digest('SHA-256', new Uint8Array([1, 2, 3])));
expect('second file hashed independently', htmlBare(root).includes(`sha256: ${expected2}`), true);
find(root, 'Upload').listeners.click();
expect('second upload sends the second file', requests[1].body === file2, true);

