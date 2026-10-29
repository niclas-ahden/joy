# Joy's `js-framework-benchmark` entry

We track Joy's rough standing in
[js-framework-benchmark](https://github.com/krausest/js-framework-benchmark) by
benchmarking locally for now. We will upstream Joy's entries to get included
in the official runs too!

We have two entries:

- **`frameworks/keyed/joy`**: the headline entry, since it plays in the same bracket as
  Elm (keyed), Leptos and React.
- **`frameworks/non-keyed/joy`**: no keys, rows are patched positionally, compared
  against Elm (non-keyed), Halogen and vanilla.

Each entry is built from its own app in this repo, `tests/apps/jsbench_keyed.roc` and
`tests/apps/jsbench_nonkeyed.roc`. They are separate apps rather than one app branching on
a flag, so neither binary carries the other's code or tests a flag per row.
`www/runtime.js` is minified with `uglify` on the way into `dist/`. The wasm is built with
`--opt=size` and `run.roc` then runs `wasm-opt -Oz` over it, so the bundle-size column
compares against the other entries' minified production builds like with like. Both
entries are built the same way, and a missing `wasm-opt` fails the run rather than
quietly measuring a bigger binary than the last one.

We build at `--opt=size` rather than `--opt=speed` because it was smaller with no
measurable loss in speed. On 2026-10-18 with Roc `nightly-2026-10-18-1df370f`, the keyed wasm
was 3% smaller raw and 2-3% smaller compressed than `--opt=speed` plus `wasm-opt -O3`.
The CPU benchmarks moved by less than their run-to-run noise. The time here goes to DOM
work, so the Roc code's opt level barely shows. `-Oz` on top of the size build only takes
off another 0.5% or so, but it costs nothing at runtime.

The entry's own `build.sh`, which builds the published entry from a Joy release, uses the
same opt level and applies the same `wasm-opt` flags through a `binaryen` dev dependency,
so it stays standalone. We must keep the two in step, because if they drift, the size we
track here and the size the published entry ships will be different.

## Releasing

The published entries track a Joy release, and when we have a new Joy version we can
bump the entries, and change the implementations as necessary. The `frameworkVersion` in
`package.json` carries the version.

Local runs should compare the currently published entry to our new local version.
`build-local.sh` compiles `tests/apps/*.roc` from the checkout, and `run.roc` labels the
results with the git commit that built them, so a snapshot says which binary produced it.

## Keeping the comparison fair

The Joy apps mirror the Elm entry, which is the closest relative (same architecture,
same per-row `lazy`): one PRNG draw per word of the label through `roc-prng`, where
Elm draws through `Random.step` and Halogen through `Math.random` in an FFI helper,
`lazy` on every row as Elm has `lazy` on every row, the same
adjective/colour/noun word lists, the same swap of indices 1 and 998, and the same
`" !!!"` suffix on every tenth row. What the apps do not do is as important: no batching
of updates, no caching of rendered rows outside what `lazy` gives every framework, and no
reading of the DOM.

The seed is a constant rather than the clock, so a run's labels are reproducible. The
benchmark never reads the labels, only the row count, the ids, and the `" !!!"` suffix,
so this changes nothing measured.

## Run it

```sh
benchmarks/jsframework/run.roc          # Joy only (reuses cached competitor results), the default for iterating
FULL=1 benchmarks/jsframework/run.roc   # also re-run Elm, Halogen, Leptos, Solid, React and vanilla
FAST=1 benchmarks/jsframework/run.roc   # Joy only, quick subset (create/swap/remove)
```

Each run rebuilds both Joy entries from the current checkout, counts their instructions,
runs the suite twice in headed Chromium (windows will flash on your display, which is
expected), and writes:

- `runs/<timestamp>/report.md`: full cross-framework tables (CPU, memory, bundle size), the
  dev vs released comparison with its noise band, and the instruction counts
- `runs/<timestamp>/rounds/`: each round's raw result JSONs
- `runs/<timestamp>/icount/`: the instruction counts of each Joy arm
- `runs/<timestamp>/results/`: the raw result JSONs as the last round left them
- `history.jsonl` + `HISTORY.md`: one row per run of Joy's headline numbers, so you can see how they move run to run

Every (framework, benchmark) pair gets its own runner invocation, in the runner's own
benchmark-outer order, so the dev and released arms still hit each benchmark seconds
apart. Between pairs the run waits until the previous pair's browser is actually gone,
reaping it by force if it lingers, so one framework's failure cannot bleed into the
next one's numbers. A pair that hangs is killed after five minutes and re-run by the
retry pass. The runner's output prints when each pair finishes rather than streaming
live.

All of it is gitignored. The numbers are one machine's under one governor setup, and
comparable only to each other.

The run records the Joy git commit it measured, so each snapshot is tied to a known version.

### Keeping the numbers stable

Every run follows the same procedure, so two runs differ only in the code and the machine.

- **CPU governor.** The run stops unless every core runs the `performance` governor
  (`sudo cpupower frequency-set -g performance`, and set it back afterwards). Under a
  governor that scales the clock with load, a timing says as much about how busy the
  machine was a moment earlier as about the code.
- **Two rounds.** The suite runs twice, the second time with the arms in reverse order,
  and the report pools both into one median per arm. One round in a fixed order is not
  enough: on 2026-10-18 keyed replace 1k came out 5% slower in one round and 4% faster in
  the next, with the same two binaries. Create 10k, which takes one sample per runner
  invocation, gets three invocations a round.
- **A noise band.** For each benchmark the report gives the dev vs released change with a
  95% bootstrap interval and the change each round saw on its own. It calls a change
  `faster` or `slower` only when the interval leaves out zero and every round moved
  the same way, and `noise` otherwise.
- **Instruction counts.** `benchmarks/icount` rewrites an entry's wasm to count the
  instructions it executes, and `icount.mjs` replays each benchmark's warmups and
  measured click on the fake DOM from `tests/`. For each click the report gives the wasm
  instructions, the calls into the DOM, and the bytes moved by `memory.copy` and
  `memory.fill`. No browser is involved, so the counts are the same on every run and
  every machine, and a change of 0.1% is a real change. They leave out the browser's
  style, layout and paint, and how well the engine compiles the wasm, so they sit beside
  the timings rather than replace them. `HISTORY.md` tracks their geomean per bracket.

Before trusting a run:

- Re-measure at least one comparison framework in the same session (`FULL=1` does all of
  them). Without a control there is no telling a Joy change from machine drift.

Memory and bundle size are stable run to run and can be compared outright.

## Prerequisites

`$JS_FRAMEWORK_BENCHMARK_DIR` must be set to a clone of `js-framework-benchmark`.

Setup the `js-framework-benchmark`: `npm ci && npm run install-local` for the server
and runner, and the comparison entries built with `npm ci && npm run build-prod` in
each of `frameworks/keyed/elm`, `frameworks/non-keyed/elm`, `frameworks/non-keyed/halogen`,
`frameworks/keyed/solid` and `frameworks/keyed/react-hooks` (`leptos` and `vanillajs`
come prebuilt). The instruction counter is a Cargo crate that the run builds on first use,
so it needs `cargo` (the dev shell has it). The Joy entries are rebuilt from this repo's checkout by each entry's
`build-local.sh`, which runs `./build.roc` here (through direnv when available, directly
otherwise). `npm ci` in a Joy entry installs its own pinned roc and binaryen, which only
`build.sh` needs.

On a standard setup that is all: node and npm come from wherever you normally get
them, webdriver-ts's `npm ci` downloads the Playwright chromium, and `run.roc` runs
the benchmark commands directly.

On NixOS the npm-downloaded chromium and the npm `elm` binary do not run, so the
clone gets a local dev shell instead:

1. Copy `clone-setup/flake.nix` and `clone-setup/flake.lock` into the clone, and
   create a `.envrc` there containing `use flake .`.
2. List `.envrc`, `flake.nix`, `flake.lock` and `.direnv/` in the clone's
   `.git/info/exclude`, so they stay out of any upstream PR.
3. `direnv allow` the clone.
4. Align Playwright versions: the flake pins browsers from nixpkgs' playwright-driver,
   and webdriver-ts must use the same driver version to find them. Bump the
   `playwright*` deps in `webdriver-ts/package.json` to the version the flake's
   shellHook note names, then re-run `npm ci` there. That package.json change also
   stays local, it is machine setup, not something to upstream.

`run.roc` detects the clone's `.envrc` and wraps the benchmark work in `direnv exec`.
Without one it runs the commands as is.

> Note: with `$PLAYWRIGHT_BROWSERS_PATH` set (the nix shell sets it) the runner is
> pointed at that chromium via `--chromeBinary`, otherwise it finds its own. The
> lighthouse `30_startup` benchmark is not run (it needs extra Chrome wiring).
> CPU/memory/size are.
