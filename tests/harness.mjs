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
import { fakeDom } from './fakedom.mjs';

// The optimization level under test. tests.roc sets JOY_OPT for the harnesses
// it spawns. There is no default: a harness must never guess which tree it is
// testing.
export const optLevel = () => {
  const opt = process.env.JOY_OPT;
  if (!opt) {
    throw new Error('JOY_OPT is not set. Run via ./tests.roc <opt>, or directly with e.g. JOY_OPT=speed node tests/check_counter.mjs');
  }
  return opt;
};

// Where build.roc put the app for the level under test.
export const wasmPath = (name) => `build/${optLevel()}/${name}.wasm`;

export const expect = (label, got, want) => {
  test(label, () => {
    assert.strictEqual(got, want);
  });
};

export const expectAtMost = (label, got, max) => {
  test(label, () => {
    assert.ok(got <= max, `${got} > ${max}`);
  });
};

// Work-budget assertions. A harness that only checks the rendered tree
// passes when a text edit rebuilds the whole list, as long as the list
// looks right afterwards. The meter also counts what a dispatch cost: the
// patch ops the differ emitted (read from the host) and the DOM mutations
// the runtime made to apply them (counted by a wrapped fake DOM). Cumulative
// since mount, so a step is measured as the delta since the last mark:
//
//   const counted = countingDom();
//   const app = await mount({ wasm, root, flags: '', dom: counted.dom });
//   const work = meter(app, counted);
//   work.mark();
//   byRole(root, 'button', '+').listeners.click();
//   work.expectDelta('incrementing', { patchSetText: 1, patchReplace: 0, elements: 0 });
//
// Metrics: elements, textNodes (created), attrWrites, attrRemovals,
// textWrites, inserts (a fresh subtree placed among kept siblings, or a
// replacement), moves (a kept node re-inserted elsewhere), removals,
// bindings (listeners attached), propWrites (live properties pinned back after
// an event, see restoreControl in www/runtime.js). Then patchSetText, patchReplace,
// patchAttrs, patchReorder, patchRefresh (ops emitted by the differ), and
// lazyForces.

// A fake DOM that counts the mutations made through it. `counts` is live.
export function countingDom(base = fakeDom) {
  const counts = {
    elements: 0, textNodes: 0, attrWrites: 0, attrRemovals: 0, textWrites: 0,
    inserts: 0, moves: 0, removals: 0, bindings: 0, propWrites: 0,
  };
  // A node still inside a build fragment is fresh, not moved.
  const live = (node) => node.parent !== null && node.parent.tag !== '#frag';
  const dom = {
    ...base,
    createElement: (tag) => { counts.elements += 1; return base.createElement(tag); },
    createText: (s) => { counts.textNodes += 1; return base.createText(s); },
    setAttr: (node, k, v) => { counts.attrWrites += 1; base.setAttr(node, k, v); },
    removeAttr: (node, k) => { counts.attrRemovals += 1; base.removeAttr(node, k); },
    setText: (node, s) => { counts.textWrites += 1; base.setText(node, s); },
    insertBefore: (parent, node, anchor) => {
      if (live(node)) counts.moves += 1; else counts.inserts += 1;
      base.insertBefore(parent, node, anchor);
    },
    replaceNode: (oldNode, newNode) => {
      counts.removals += 1;
      counts.inserts += 1;
      base.replaceNode(oldNode, newNode);
    },
    removeChild: (parent, node) => { counts.removals += 1; base.removeChild(parent, node); },
    clear: (node) => { counts.removals += node.children.length; base.clear(node); },
    on: (node, event, fn) => { counts.bindings += 1; base.on(node, event, fn); },
    setProp: (node, k, v) => { counts.propWrites += 1; base.setProp(node, k, v); },
  };
  return { dom, counts };
}

export function meter(app, counted) {
  const ex = app.instance.exports;
  if (typeof ex.patch_ops !== 'function') {
    throw new Error('meter: this wasm has no patch_ops export, rebuild it with ./build.roc');
  }
  const snapshot = () => ({
    ...counted.counts,
    patchSetText: ex.patch_ops(0),
    patchReplace: ex.patch_ops(1),
    patchAttrs: ex.patch_ops(2),
    patchReorder: ex.patch_ops(3),
    patchRefresh: ex.patch_ops(4),
    lazyForces: ex.lazy_forces(),
  });
  let marked = snapshot();
  const delta = () => {
    const now = snapshot();
    const d = {};
    for (const k of Object.keys(now)) d[k] = now[k] - marked[k];
    return d;
  };
  const check = (label, want, assertOne) => {
    const d = delta();
    for (const [k, v] of Object.entries(want)) {
      if (!(k in d)) throw new Error(`meter: unknown metric \`${k}\`, expected one of ${Object.keys(d).join(', ')}`);
      assertOne(`${label}: ${k}`, d[k], v);
    }
  };
  return {
    // Start measuring the next step from here.
    mark: () => { marked = snapshot(); },
    // Every metric's change since the mark.
    delta,
    // Exact budgets, one test case per metric named.
    expectDelta: (label, want) => check(label, want, expect),
    // Upper bounds, for steps whose exact cost is not the point.
    expectDeltaAtMost: (label, caps) => check(label, caps, expectAtMost),
  };
}
