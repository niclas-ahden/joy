// Node harness for jsbench, the js-framework-benchmark table app. Asserts the
// same DOM facts the benchmark runner's driver checks (row counts, ids, the
// danger class, the " !!!" update, swap, remove, clear), in both the keyed and
// non-keyed configurations, plus the identity behaviour each bracket promises.
// Run from the repo root: node tests/check_jsbench.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, findTag } from './fakedom.mjs';
import { expect } from './harness.mjs';

const bytes = readFileSync('build/jsbench.wasm');

// First element with the given id attribute (pre-order).
function findId(node, id) {
  if (!(node instanceof El)) return null;
  if (node.attrs?.get('id') === id) return node;
  for (const c of node.children) {
    const hit = findId(c, id);
    if (hit) return hit;
  }
  return null;
}

async function checkBracket(keyed) {
  const tag = keyed ? 'keyed' : 'non-keyed';
  const root = new El('#root');
  await mount({ wasm: bytes, root, flags: JSON.stringify({ keyed }), dom: fakeDom });

  const tbody = findId(root, 'tbody');
  const rows = () => tbody.children;
  const rowId = (tr) => tr.children[0].children[0].text;
  const rowLabel = (tr) => tr.children[1].children[0].children[0].text;
  const click = (id) => findId(root, id).listeners.click();

  expect(`${tag}: starts empty`, rows().length, 0);

  click('run');
  expect(`${tag}: create 1k`, rows().length, 1000);
  expect(`${tag}: ids start at 1`, rowId(rows()[0]), '1');
  expect(`${tag}: key never reaches the DOM`, rows()[0].attrs.has('key'), false);

  // Row 1 (the second row) gets selected by clicking its label link.
  rows()[1].children[1].children[0].listeners.click();
  expect(`${tag}: selected row gets danger`, rows()[1].attrs.get('class'), 'danger');
  expect(`${tag}: other rows unselected`, rows()[0].attrs.has('class'), false);

  click('update');
  expect(`${tag}: update appends !!! to every 10th`, rowLabel(rows()[0]).endsWith(' !!!'), true);
  expect(`${tag}: update leaves the 9 in between`, rowLabel(rows()[1]).endsWith(' !!!'), false);
  expect(`${tag}: update hits row 10`, rowLabel(rows()[10]).endsWith(' !!!'), true);

  const [idAt1, idAt998] = [rowId(rows()[1]), rowId(rows()[998])];
  const [nodeAt1, nodeAt998] = [rows()[1], rows()[998]];
  click('swaprows');
  expect(`${tag}: swap moves 1 to 998`, rowId(rows()[998]), idAt1);
  expect(`${tag}: swap moves 998 to 1`, rowId(rows()[1]), idAt998);
  if (keyed) {
    expect('keyed: swap moves the row nodes themselves', rows()[998] === nodeAt1 && rows()[1] === nodeAt998, true);
  } else {
    expect('non-keyed: swap patches rows in place', rows()[1] === nodeAt1 && rows()[998] === nodeAt998, true);
  }
  expect(`${tag}: danger follows the selected id through the swap`, rows()[998].attrs.get('class'), 'danger');

  const removedId = rowId(rows()[3]);
  rows()[3].children[2].children[0].listeners.click();
  expect(`${tag}: remove drops one row`, rows().length, 999);
  expect(`${tag}: removed id is gone`, rows().some((tr) => rowId(tr) === removedId), false);

  click('add');
  expect(`${tag}: append 1k`, rows().length, 1999);
  expect(`${tag}: appended ids continue`, rowId(rows()[1998]), '2000');

  click('clear');
  expect(`${tag}: clear empties the table`, rows().length, 0);

  click('runlots');
  expect(`${tag}: create 10k`, rows().length, 10000);
  expect(`${tag}: 10k ids continue from id source`, rowId(rows()[0]), '2001');

  click('clear');
  expect(`${tag}: clear after 10k`, rows().length, 0);
}

await checkBracket(true);
await checkBracket(false);
