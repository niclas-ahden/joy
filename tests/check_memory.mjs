// Memory-stability harness: drives thousands of update/render cycles through
// several apps and asserts the host heap's high-water mark (heap_used) stops
// growing once the free lists are warm. This is the proof that the
// refcounting discipline is balanced: any missing decref shows up as a
// steadily climbing watermark, any extra decref as a crash or corruption in
// the functional checks.
// Run from the repo root: node tests/check_memory.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, fakeDom, find, findTag, htmlBare, activeGlobalListeners } from './fakedom.mjs';
import { expect } from './harness.mjs';

// Warm up with `warm` iterations, then measure across `measure` more.
// Returns [watermarkAfterWarmup, watermarkAtEnd].
const run = (iterations, step, exportsRef) => {
  for (let i = 0; i < iterations; i++) step(i);
  return exportsRef.heap_used();
};

// --- counter: msg events, diff, model churn ---
{
  const root = new El('#root');
  const { instance } = await mount({ wasm: readFileSync('build/counter.wasm'), root, flags: '', dom: fakeDom });
  const plus = find(root, '+');
  const click = () => plus.listeners.click();
  const afterWarmup = run(2000, click, instance.exports);
  const atEnd = run(5000, click, instance.exports);
  expect('counter: heap stable across 5000 clicks', atEnd - afterWarmup, 0);
  expect('counter: still correct', htmlBare(root).includes('7000'), true);
}

// --- events_input: value events, big strings through js_alloc ---
{
  const root = new El('#root');
  const { instance } = await mount({ wasm: readFileSync('build/events_input.wasm'), root, flags: '', dom: fakeDom });
  const ta = findTag(root, 'textarea');
  const realLog = console.log;
  console.log = () => {};
  const type = (i) => ta.listeners.input({ target: { value: `entry ${i}: ${'x'.repeat(200)}` } });
  const afterWarmup = run(300, type, instance.exports);
  const atEnd = run(700, type, instance.exports);
  console.log = realLog;
  expect('events_input: heap stable across 700 long inputs', atEnd - afterWarmup, 0);
}

// --- http: command queue, response bodies, one-shot callback release ---
{
  globalThis.fetch = () => Promise.resolve({
    status: 200,
    arrayBuffer: async () => new TextEncoder().encode(`["${'q'.repeat(300)}"]`).buffer,
  });
  const root = new El('#root');
  const { instance } = await mount({ wasm: readFileSync('build/http.wasm'), root, flags: '', dom: fakeDom });
  const realLog = console.log;
  console.log = () => {};
  const tick = () => new Promise((r) => setTimeout(r, 0));
  const cycle = async () => {
    find(root, 'Treat Yo Self').listeners.click();
    await tick();
    await tick();
  };
  for (let i = 0; i < 50; i++) await cycle();
  const afterWarmup = instance.exports.heap_used();
  for (let i = 0; i < 100; i++) await cycle();
  const atEnd = instance.exports.heap_used();
  console.log = realLog;
  delete globalThis.fetch;
  expect('http: steady-state heap growth is zero', atEnd - afterWarmup, 0);
}

// --- time: a subscription's callback swaps on every tick ---
{
  const intervals = [];
  const realSetInterval = globalThis.setInterval;
  globalThis.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
  const root = new El('#root');
  const { instance } = await mount({ wasm: readFileSync('build/time.wasm'), root, flags: '', dom: fakeDom });
  const tickFn = intervals[0].fn;
  const afterWarmup = run(500, tickFn, instance.exports);
  const atEnd = run(1500, tickFn, instance.exports);
  globalThis.setInterval = realSetInterval;
  expect('time: heap stable across 1500 ticks', atEnd - afterWarmup, 0);
  // Every dealloc found its span: a miss means the compiler handed
  // roc_dealloc a pointer the span recovery could not resolve (silent leak).
  expect('time: no unresolvable deallocs', instance.exports.dealloc_miss(), 0);
}

// --- keyboard: subscription churn (identity blobs + callback lists
// start/stop) plus fan-out dispatch (each event feeds two callbacks, so the
// KeyEvent record's heap strings are increfed per extra callback) ---
{
  const root = new El('#root');
  const { instance } = await mount({ wasm: readFileSync('build/keyboard.wasm'), root, flags: '', dom: fakeDom });
  const toggle = () => {
    (find(root, 'Stop listening') ?? find(root, 'Listen')).listeners.click();
  };
  // key and code both exceed the 11-byte inline-string limit, so every
  // dispatch allocates two heap strings that the callbacks must consume.
  const fire = () => {
    const e = { key: 'AudioVolumeDown', code: 'AudioVolumeDown', preventDefault: () => {} };
    for (const l of activeGlobalListeners()) l.fn(e);
    toggle();
  };
  const afterWarmup = run(200, fire, instance.exports);
  const atEnd = run(600, fire, instance.exports);
  expect('keyboard: heap stable across 600 fire+toggle cycles', atEnd - afterWarmup, 0);
  expect('keyboard: no unresolvable deallocs', instance.exports.dealloc_miss(), 0);
}

