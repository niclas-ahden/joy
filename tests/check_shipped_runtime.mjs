// Node harness for what an app ships: runtime.js as written, without comments or
// indentation, and nothing of hot reloading in it or in the wasm. tests/check_hot*.mjs
// run on the runtime.js for development, and every other harness on the one an app
// ships.
// Run from the repo root: JOY_OPT=speed node tests/check_shipped_runtime.mjs
import { readFileSync } from 'node:fs';
import { expect, plainWasmPath, runtimePath } from './harness.mjs';

const lines = (text) => text.split('\n').map((line) => line.trim()).filter((line) => line !== '' && !line.startsWith('//'));

const shipped = lines(readFileSync(runtimePath('counter'), 'utf8'));
const source = lines(readFileSync('www/runtime.js', 'utf8'));
// The source is first, whole and as written, and only features come after it.
expect('shipped runtime.js: the source as written', shipped.slice(0, source.length).join('\n') === source.join('\n'), true);
const text = shipped.join('\n');
for (const word of ['__JOY_HOT__', 'hotOps', 'hooks', 'JOY_DEV_PORT']) {
  expect(`shipped runtime.js: no ${word}`, text.includes(word), false);
}

const development = readFileSync(`build/${process.env.JOY_OPT}/runtime.js`, 'utf8');
expect('the development runtime.js has the hooks', development.includes('__JOY_HOT__') && development.includes('handle.hooks = {'), true);
expect('the development runtime.js has no seam left open', /\/\/ hot:(runtime|mount)/.test(development), false);

const exports = WebAssembly.Module.exports(new WebAssembly.Module(readFileSync(plainWasmPath('counter')))).map((e) => e.name);
expect('shipped wasm: no hot exports', exports.filter((name) => name.startsWith('hot_')).length, 0);
