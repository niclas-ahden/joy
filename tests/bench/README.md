# Phase regression benchmark

A local tool, run by hand and compared against a saved baseline, the same way
`cargo bench --baseline` works. There is no CI gate (a noisy shared runner
makes these timings unreliable anyway).

`bench.roc` builds the jsbench app with the host's `joy_bench` instrumentation
(`JOY_BENCH=1 ./build.roc -- --opt=speed`), serves it, and drives update steps in headless
Chromium. Each step's cost is split into the phases we own end to end:

- **update**: the app's `update` runs (`roc_update`, plus effect handling)
- **render**: the app's `render` builds the new tree (`roc_render`)
- **diff**: the host diffs new against previous and emits patch ops
- **paint**: the runtime (`www/runtime.js`) applies the ops to the real DOM

If a number moves, this tells you *which* layer moved: `update`/`render` point
at the app or Roc codegen, `diff` at the differ in `host/host.rs`, `paint` at
the runtime's command interpreter. The workload (update every 10th of 1000
rows) is the same one the js-framework-benchmark measures, so these phases
explain movements in `benchmarks/jsframework/` numbers directly.

```sh
tests/bench/bench.roc                  # run and compare against baseline.json
tests/bench/bench.roc --save-baseline  # accept the current numbers as the new baseline
```

Tunables (env): `BENCH_STEPS` (default 200), `BENCH_WARMUP` (default 30),
`BENCH_PORT` (default 8788), `BENCH_THRESHOLD` (slowdown ratio that prints
`REGRESSION`, default 1.10).

Needs the nix devShell (playwright + browsers), the same requirement as
`e2e.roc`.

`performance.now()` is deliberately coarsened by browsers (0.1 ms steps), so
phases can quantize and single-digit-percent moves are noise: re-run before
trusting a regression, and prefer a larger `BENCH_STEPS` when chasing a small
one. The instrumentation is compiled out entirely without `JOY_BENCH`, so
normal builds pay nothing and stay import-free.

For a quicker inner loop without a browser (and without the paint phase being
a real DOM), `tests/bench_render.mjs` times whole dispatches against the fake
DOM in Node.
