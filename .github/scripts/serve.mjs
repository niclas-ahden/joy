// Serve one directory over plain HTTP on 127.0.0.1, so roc can fetch a
// drafted bundle the way it fetches a published one.
//
//   node .github/scripts/serve.mjs <dir> <port>
//
// node rather than python because every leg already has node for the
// harnesses, and a Windows runner's python is not reliably `python3`.
import { createServer } from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import { basename, join } from 'node:path';

const [dir, port] = process.argv.slice(2);

createServer((req, res) => {
  const file = join(dir, basename(decodeURIComponent(req.url)));
  let size;
  try {
    size = statSync(file).size;
  } catch {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'content-length': size, 'content-type': 'application/octet-stream' });
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  createReadStream(file).pipe(res);
}).listen(Number(port), '127.0.0.1');
