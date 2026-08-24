// Node harness for the stack overflow canary: the host keeps a canary band
// near the shadow stack's floor (see host.rs) and the runtime kills the
// instance when a dispatch crosses it. Drives tests/apps/deep.roc, whose
// flags set how deep one click nests the view.
// Run from the repo root: node tests/check_stack_canary.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, html, find } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const wasm = readFileSync(wasmPath('deep'));

// The depth every build promises to nest without either guard firing, set
// well under the lowest ceiling measured so far. Two different limits race
// here and which one binds first moves with the engine and the opt level:
// deep recursion drains the shadow stack and the engine's native stack
// together. In Node the native stack usually binds (RangeError) and it is
// shallower on macOS than on linux; in a dev build the shadow stack binds
// first (the canary), because an unoptimized level costs ~360 bytes of it
// against ~95 optimized. Both ceilings sit near 3000 at their lowest, so a
// promise tuned at 4000 against linux and speed went red on macOS and on
// dev with no regression behind it. The scans below measure where the
// ceiling actually sits today and print it.
const budget = 1500;

const mountDeep = async (depth) => {
  const root = new El('#root');
  const app = await mount({ wasm, root, flags: String(depth), dom: fakeDom });
  return { root, app, go: () => find(root, 'go').listeners.click() };
};

const clickOutcome = (go) => {
  try {
    go();
    return 'ok';
  } catch (err) {
    return err.message.includes('shadow stack overflowed') ? 'canary' : `threw: ${err.constructor.name}`;
  }
};

// Deep nesting inside the budget renders fine and leaves the canary alone.
// The 500 case is shallow enough for fakedom's recursive serializer, the
// budget case exercises the wasm side only.
{
  const { root, go } = await mountDeep(500);
  go();
  expect('500 levels render inside the budget', (html(root).match(/<div>/g) ?? []).length, 500);
}
{
  const { app, go } = await mountDeep(budget);
  expect(`${budget} levels dispatch inside the budget`, clickOutcome(go), 'ok');
  expect('canary intact after a deep render', app.instance.exports.stack_canary_ok(), 1);
  // The second click re-renders the same depth, so the differ walks two
  // trees in lockstep. That recursion carries diff_children's scratch frame
  // at every level, making it the deepest-framed path the host has: first
  // renders take the cheap REPLACE path and never see it.
  expect(`${budget} levels re-diff inside the budget`, clickOutcome(go), 'ok');
  expect('canary intact after a deep re-diff', app.instance.exports.stack_canary_ok(), 1);
}

// Corrupting the band by hand proves the detection path end to end: the next
// dispatch throws the overflow error and the instance is dead afterwards.
{
  const { root, app, go } = await mountDeep(3);
  const ex = app.instance.exports;
  new Uint32Array(ex.memory.buffer, ex.stack_floor(), 1)[0] = 0;
  expect('poked canary turns the next dispatch into the overflow error', clickOutcome(go), 'canary');
  const before = html(root);
  go();
  expect('a dead instance ignores further dispatches', html(root), before);
}

// A real overflow, scanned upwards from the budget in 100-level increments
// so the first failure cannot leap the 12 KB of band plus margin (one level
// costs ~95 bytes of shadow stack optimized). The canary error means the
// shadow stack emptied first (the band scan or the alloc-time trap in
// roc_alloc, both surface as this error), RangeError means the native stack
// did. Both are loud failures. Starting at the budget rather than above it
// keeps the ceiling check honest: a ceiling that has sunk to the budget
// reports the budget instead of the step above it.
{
  let outcome = 'never failed';
  let at = 0;
  for (let depth = budget; depth <= 30000; depth += 100) {
    const { go } = await mountDeep(depth);
    const result = clickOutcome(go);
    if (result !== 'ok') {
      outcome = result;
      at = depth;
      break;
    }
  }
  const loud = outcome === 'canary' || outcome === 'threw: RangeError';
  expect(`a real overflow fails loudly (got: ${outcome} at depth ${at})`, loud, true);
  expect('the render ceiling clears the promised budget', at > budget, true);
}

// The diff path has its own, lower ceiling: re-rendering an already-deep
// tree recurses diff and diff_children in lockstep, and diff_children's
// frame carries a scratch buffer, so a diffed level costs several times a
// rendered one. This drives past that ceiling on purpose: the first click
// builds (cheap REPLACE path), the second re-diffs at full depth, stepped
// in 40-level increments for the same never-leap-the-band reason as above.
// The label records roughly where the ceiling sits today, which is what
// catches a diff frame growing fat enough to shrink how deep apps can nest.
{
  let outcome = 'never failed';
  let at = 0;
  for (let depth = budget; depth <= 12000; depth += 40) {
    const { go } = await mountDeep(depth);
    let result = clickOutcome(go);
    if (result === 'ok') result = clickOutcome(go);
    if (result !== 'ok') {
      outcome = result;
      at = depth;
      break;
    }
  }
  const loud = outcome === 'canary' || outcome === 'threw: RangeError';
  expect(`a re-diff overflow fails loudly (got: ${outcome} at depth ${at})`, loud, true);
  expect('the re-diff ceiling clears the promised budget', at > budget, true);
}

// Far past the budget the overflow is caught mid-dispatch, by the alloc-time
// check or the engine's own limit, whichever binds first. Still loud: the
// dispatch throws and the app dies instead of running on corrupted memory.
{
  const { go } = await mountDeep(1000000);
  const result = clickOutcome(go);
  expect('a huge overflow still fails loudly', result !== 'ok', true);
}
