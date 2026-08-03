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

export const expect = (label, got, want) => {
  test(label, () => {
    assert.strictEqual(got, want);
  });
};
