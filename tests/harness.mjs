// node:test adapter shared by the check_*.mjs harnesses.
//
// Each harness drives the app at module load (mount, clicks, ticks) and calls
// expect() at checkpoints. expect() captures the already-evaluated got/want
// and registers a named node:test case that just compares them, so the
// driving stays strictly sequential while every assertion is reported
// individually and one failure doesn't hide the rest.
//
// Run one harness directly with `node tests/check_foo.mjs` (the exit code
// reflects failures) or the whole suite via `node --test tests/check_*.mjs`
// (one child process per file, files run concurrently).
import test from 'node:test';
import assert from 'node:assert/strict';

// Where build.roc put the app for the optimization level under test.
// tests.roc sets JOY_OPT for the harnesses it spawns. There is no default:
// a harness must never guess which tree it is testing.
export const wasmPath = (name) => {
  const opt = process.env.JOY_OPT;
  if (!opt) {
    throw new Error('JOY_OPT is not set. Run via ./tests.roc <opt>, or directly with e.g. JOY_OPT=speed node tests/check_counter.mjs');
  }
  return `build/${opt}/${name}.wasm`;
};

export const expect = (label, got, want) => {
  test(label, () => {
    assert.strictEqual(got, want);
  });
};
