# js-framework-benchmark tracking

Joy's standing in the [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark)
"table" benchmark, tracked over time so we can see whether a change helps or hurts.

Joy is entered as **`frameworks/non-keyed/joy`** in a local clone of the benchmark
(`$JS_FRAMEWORK_BENCHMARK_DIR`, set in this repo's `.envrc`; see `BENCHMARK.md`), compared against
vanilla JS, Elm (keyed + non-keyed), Leptos, and React. Joy is non-keyed (percy diffs
children by position).

## Run it

```sh
benchmarks/jsframework/run.sh          # Joy only (reuses cached competitor results); the default for iterating
FULL=1 benchmarks/jsframework/run.sh   # also re-run vanilla/Elm/Leptos/React (milestone / version refresh)
FAST=1 benchmarks/jsframework/run.sh   # Joy only, quick subset (create/swap/remove)
```

Each run rebuilds the Joy entry from the current Joy checkout, runs the suite in headed
Chromium (windows will flash on your display — expected), and writes:

- `runs/<timestamp>/report.md` — full cross-framework tables (CPU, memory, bundle size) for that run
- `runs/<timestamp>/results/` — the raw result JSONs
- `history.jsonl` + `HISTORY.md` — one row per run of Joy's headline numbers, so improvements/regressions are visible at a glance

The run records the Joy git commit it measured, so each snapshot is tied to a known version.

## Metrics

- **CPU** — median operation duration in ms (create/replace/update/select/swap/remove/clear, 1k & 10k rows). The headline is the **geomean** and the **slowdown vs the fastest framework** on each benchmark.
- **Memory** — heap MB at various points.
- **Bundle size** — compressed transfer KB.

## Prerequisites

The `$JS_FRAMEWORK_BENCHMARK_DIR` clone must be set up once: its flake dev shell (node/npm
+ roc/zig/wasm-pack + Playwright browsers), `npm run install-local` for the runner, and
the comparison entries built (`elm`, `react-hooks`, `leptos` is prebuilt). `run.sh` wraps
its work in `direnv exec`, so that repo just needs to have been `direnv allow`ed.

> Note: the runner launches real Chrome via `--chromeBinary`; `run.sh` points it at the
> nix-provided chromium under `$PLAYWRIGHT_BROWSERS_PATH`. The lighthouse `30_startup`
> benchmark is not run (it needs extra Chrome wiring); CPU/memory/size are.
