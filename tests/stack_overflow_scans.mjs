// The deep recursion half of check_stack_overflow.mjs, which runs this file
// in a worker with a native stack far deeper than the shadow stack, so the
// shadow stack always runs out first. Drives tests/apps/deep.roc, whose
// flags set how deep one click nests the view, and posts its checks back as
// { label, got, want } for the main thread to report. It mounts on the
// runtime.js build.roc generated for the app, the one the app would ship.
import { readFileSync } from 'node:fs';
import { parentPort, workerData } from 'node:worker_threads';
import { El, fakeDom, html, find } from './fakedom.mjs';

const { mount } = await import(`../${workerData.runtime}`);

const checks = [];
const check = (label, got, want) => checks.push({ label, got, want });

const wasm = readFileSync(workerData.wasm);

// The depth every build promises to nest without overflowing, set well under
// the lowest ceiling measured so far. A dev level costs ~360 bytes of shadow
// stack against ~48 optimized, so the dev re-diff ceiling sits lowest, near
// 2,700. A browser's native stack can bind before the shadow stack does, so
// the promise has to hold well inside both (see tests/e2e/stack_depth_test.roc).
// The scans below measure where the ceiling actually sits today and print it.
const budget = 1500;

const mountDeep = async (depth) => {
  const root = new El('#root');
  const app = await mount({ wasm, root, flags: String(depth), dom: fakeDom });
  return { root, app, go: () => find(root, 'go').listeners.click() };
};

// 'trap' is the shadow stack running out: the stack pointer wraps below 0
// and the next store lands out of bounds. The runtime wraps the engine's
// error in its own crash error, so both are checked.
const clickOutcome = (go) => {
  try {
    go();
    return 'ok';
  } catch (err) {
    const trap = err.message.startsWith('Joy: the app crashed')
      && err.cause instanceof WebAssembly.RuntimeError
      && err.cause.message === 'memory access out of bounds';
    if (trap) return 'trap';
    return `threw: ${err.message}${err.cause ? ` (cause: ${err.cause.message})` : ''}`;
  }
};

// Deep nesting inside the budget renders fine. The 500 case is shallow
// enough for fakedom's recursive serializer, the budget case exercises the
// wasm side only.
{
  const { root, go } = await mountDeep(500);
  go();
  check('500 levels render inside the budget', (html(root).match(/<div>/g) ?? []).length, 500);
}
{
  const { go } = await mountDeep(budget);
  check(`${budget} levels dispatch inside the budget`, clickOutcome(go), 'ok');
  // The second click re-renders the same depth, so the differ walks two
  // trees in lockstep. That recursion carries diff_children's scratch frame
  // at every level, making it the deepest-framed path the host has: first
  // renders take the cheap REPLACE path and never see it.
  check(`${budget} levels re-diff inside the budget`, clickOutcome(go), 'ok');
}

// A real overflow, scanned upwards from the budget in 100-level increments.
// Starting at the budget rather than above it keeps the ceiling check
// honest: a ceiling that has sunk to the budget reports the budget instead
// of the step above it. The instance that overflowed is dead afterwards.
{
  let outcome = 'never failed';
  let at = 0;
  let failed = null;
  for (let depth = budget; depth <= 40000; depth += 100) {
    const deep = await mountDeep(depth);
    const result = clickOutcome(deep.go);
    if (result !== 'ok') {
      outcome = result;
      at = depth;
      failed = deep;
      break;
    }
  }
  check(`a real overflow traps (ceiling: depth ${at})`, outcome, 'trap');
  check('the render ceiling clears the promised budget', at > budget, true);
  // Compared shallowly: the tree may be too deep for fakedom's serializer.
  if (failed) {
    const before = [...failed.root.children[0].children];
    check('a dead instance ignores further dispatches', clickOutcome(failed.go), 'ok');
    const after = failed.root.children[0].children;
    check('a dead instance leaves the DOM alone', after.length === before.length && after.every((c, i) => c === before[i]), true);
  }
}

// The diff path has its own, lower ceiling: re-rendering an already-deep
// tree recurses diff and diff_children in lockstep, and diff_children's
// frame carries a scratch buffer, so a diffed level costs several times a
// rendered one. This drives past that ceiling on purpose: the first click
// builds (cheap REPLACE path), the second re-diffs at full depth, stepped
// in 40-level increments. The label records roughly where the ceiling sits
// today, which is what catches a diff frame growing fat enough to shrink
// how deep apps can nest.
{
  let outcome = 'never failed';
  let at = 0;
  for (let depth = budget; depth <= 40000; depth += 40) {
    const { go } = await mountDeep(depth);
    let result = clickOutcome(go);
    if (result === 'ok') result = clickOutcome(go);
    if (result !== 'ok') {
      outcome = result;
      at = depth;
      break;
    }
  }
  check(`a re-diff overflow traps (ceiling: depth ${at})`, outcome, 'trap');
  check('the re-diff ceiling clears the promised budget', at > budget, true);
}

// Far past the budget the overflow still traps on the first frame that
// wraps, and the app dies instead of running on corrupted memory.
{
  const { go } = await mountDeep(1000000);
  check('a huge overflow still traps', clickOutcome(go), 'trap');
}

parentPort.postMessage(checks);
