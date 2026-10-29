// Node harness for stack overflows. Roc links wasm32 with --stack-first, so
// the shadow stack sits below static data and grows down toward 0, and an
// overflow traps out of bounds instead of corrupting memory. The runtime
// kills the instance on any trap.
//
// The layout is read straight from the built module, since a Roc update
// that dropped --stack-first would otherwise only show up as silent
// corruption. The deep recursion runs in tests/stack_overflow_scans.mjs, in
// a worker: the main thread's native stack (~1 MB) runs out before the 1 MiB
// shadow stack does in optimized builds, which ends the scans in a
// RangeError and never reaches the trap they are meant to prove.
// Run from the repo root: node tests/check_stack_overflow.mjs
import { readFileSync } from 'node:fs';
import { Worker } from 'node:worker_threads';
import { expect, runtimePath, wasmPath } from './harness.mjs';

// The initial stack pointer and the lowest active data segment offset, read
// from the binary. wasm-ld always emits __stack_pointer as global 0.
const layout = (bytes) => {
  let at = 8;
  const leb = (signed) => {
    let result = 0;
    let shift = 0;
    let b;
    do {
      b = bytes[at++];
      result |= (b & 0x7f) << shift;
      shift += 7;
    } while (b & 0x80);
    if (signed && shift < 32 && (b & 0x40)) result |= -1 << shift;
    return result >>> 0;
  };
  const uleb = () => leb(false);
  const constExpr = () => {
    if (bytes[at++] !== 0x41) throw new Error('expected an i32.const expression');
    const value = leb(true);
    if (bytes[at++] !== 0x0b) throw new Error('expected the end of a constant expression');
    return value;
  };
  let stackTop = null;
  const dataOffsets = [];
  while (at < bytes.length) {
    const id = bytes[at++];
    const size = uleb();
    const end = at + size;
    if (id === 6) {
      uleb(); // count
      const type = bytes[at++];
      const mutable = bytes[at++];
      if (type !== 0x7f || mutable !== 1) throw new Error('global 0 is not a mutable i32');
      stackTop = constExpr();
    } else if (id === 11) {
      const count = uleb();
      for (let i = 0; i < count; i++) {
        const flags = uleb();
        if (flags === 2) uleb(); // memory index
        if (flags !== 1) dataOffsets.push(constExpr());
        const length = uleb();
        at += length;
      }
    }
    at = end;
  }
  return { stackTop, dataOffsets };
};

// Every app goes through the same linker, so one module stands for all.
{
  const { stackTop, dataOffsets } = layout(readFileSync(wasmPath('deep')));
  expect('the stack pointer starts below static data', stackTop !== null && dataOffsets.every((offset) => offset >= stackTop), true);
}

// The worker's stack is set explicitly, far past what 1 MiB of shadow stack
// can recurse through, so the outcome never depends on Node's default.
const checks = await new Promise((resolve, reject) => {
  const worker = new Worker(new URL('./stack_overflow_scans.mjs', import.meta.url), {
    workerData: { wasm: wasmPath('deep'), runtime: runtimePath('deep') },
    resourceLimits: { stackSizeMb: 64 },
  });
  worker.once('message', resolve);
  worker.once('error', reject);
});
for (const { label, got, want } of checks) expect(label, got, want);
