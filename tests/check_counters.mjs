// Node harness for counters: three independent counters whose messages carry
// payloads (UserClickedIncrement(Left) etc.), plus style attributes.
// Run from the repo root: node tests/check_counters.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, htmlBare, find } from './fakedom.mjs';
import { expect } from './harness.mjs';

const root = new El('#root');
await mount({ wasm: readFileSync('build/counters.wasm'), root, flags: '', dom: fakeDom });

// Structure: div > ul(left) ul(middle) ul(right); each ul > li(-) li(value) li(+)
const outer = root.children[0];
const uls = outer.children;
expect('three counters', uls.length, 3);
const valueOf = (i) => uls[i].children[1].children[0].text;
expect('left starts at -10', valueOf(0), '-10');
expect('middle starts at 0', valueOf(1), '0');
expect('right starts at 10', valueOf(2), '10');

// Styles came through as real attributes.
expect('outer div is styled', outer.attrs.get('style'), 'display: flex; justify-content: space-around; padding: 20px');
expect('minus button styled', uls[0].children[0].children[0].attrs.get('style')?.includes('background-color: red'), true);

// Click buttons in specific counters; payload variants must route correctly.
const clickIn = (ul, label) => { const el = find(ul, label); el.listeners.click(); };
clickIn(uls[0], '+'); // left++
clickIn(uls[0], '+'); // left++
clickIn(uls[2], '-'); // right--
expect('left incremented twice', valueOf(0), '-8');
expect('middle untouched', valueOf(1), '0');
expect('right decremented once', valueOf(2), '9');

// The three uls must have been diffed in place, not rebuilt.
expect('structure preserved', htmlBare(root).startsWith('<div><ul>'), true);
expect('left ul reused', uls[0] === root.children[0].children[0], true);

