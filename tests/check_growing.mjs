// Node harness for a value that grows a little with every update: a text
// with one more line each time, joined anew for the view and carried in the
// model. Each version is freed when the next is made, and the app's memory
// has to stay near the size of what it holds, not of everything it ever
// held (see large_size in host/host.rs).
// Run from the repo root: JOY_OPT=speed node tests/check_growing.mjs
import { readFileSync } from 'node:fs';
import { El, byId, fakeDom } from './fakedom.mjs';
import { appRuntime, expect, expectAtMost, wasmPath } from './harness.mjs';

const { mount } = await appRuntime('growing');
const root = new El('#root');
const app = await mount({ wasm: readFileSync(wasmPath('growing')), root, flags: '', dom: fakeDom });
const add = byId(root, 'add');
const memory = () => app.instance.exports.memory.buffer.byteLength;

for (let i = 0; i < 4_000; i++) add.listeners.click();
expect('every line is there', byId(root, 'count').children[0].text, '4000');
// The two texts end at about 100 KB each. Memory that kept every version
// they went through would be past 300 MB by now.
const after = memory();
expectAtMost('memory is a few times what the app holds (bytes)', after, 12 * 1024 * 1024);

for (let i = 0; i < 4_000; i++) add.listeners.click();
expectAtMost('and grows with what it holds, not with the clicks (bytes)', memory(), 3 * after);
expect('no free went astray', app.instance.exports.dealloc_miss(), 0);
