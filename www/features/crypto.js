// Hashing with the browser's Web Crypto, for the platform's WebCrypto
// module: bytes the app sends, or a byte range of a browser-held file whose
// bytes never enter the app. The answer is the raw hash.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// op joy/crypto/digest
defineOperation('joy/crypto/digest', async (args) => {
  const algorithm = args.str();
  const data = args.bytes();
  return new Uint8Array(await crypto.subtle.digest(algorithm, data));
});

//// helper digest_queue
// File digests waiting for a turn, and how many are reading or hashing now.
// A digest holds its whole slice in memory until the hash is done, so at
// most navigator.hardwareConcurrency run at once: an app that asks for
// every 16 MiB chunk of a 10 GB file at once then holds a few chunks, not
// the file. This is the one state apps on a page share, as the limit is on
// the machine and not on an app.
const digestQueue = [];
let digestsRunning = 0;

// A file's byte range as a Blob: len 0 means through the end of the file.
function sliceFile(file, start, len) {
  if (len > 0) return file.slice(start, start + len);
  return start > 0 ? file.slice(start) : file;
}

// Start queued digests while fewer than navigator.hardwareConcurrency run
// (read at each start, 4 where the browser does not say). A finished one
// makes room for the next, also when it failed.
function startDigests() {
  const limit = Math.max(1, globalThis.navigator?.hardwareConcurrency || 4);
  while (digestsRunning < limit && digestQueue.length > 0) {
    const { slice, algorithm, resolve, reject } = digestQueue.shift();
    digestsRunning++;
    slice
      .arrayBuffer()
      .then((buf) => crypto.subtle.digest(algorithm, buf))
      .then((hash) => resolve(new Uint8Array(hash)), reject)
      .finally(() => {
        digestsRunning--;
        startDigests();
      });
  }
}

//// op joy/crypto/digest_file needs digest_queue
defineOperation('joy/crypto/digest_file', (args, host) => {
  const algorithm = args.str();
  const fileId = args.u32();
  const start = args.u64();
  const len = args.u64();
  const file = host.file(fileId);
  if (!file) throw new Error(`no file ${fileId}`);
  return new Promise((resolve, reject) => {
    digestQueue.push({ slice: sliceFile(file, start, len), algorithm, resolve, reject });
    startDigests();
  });
});
