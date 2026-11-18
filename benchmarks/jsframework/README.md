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

## Comparing with an earlier version

`run.roc` measures this checkout against whatever the clone's released entries hold.
`compare.roc` puts any earlier version of Joy there for the length of the comparison:

```sh
benchmarks/jsframework/compare.roc 0.34.0                 # three runs, about an hour and a half
RUNS=1 benchmarks/jsframework/compare.roc 0.34.0          # one run, about half an hour
FAST=1 RUNS=1 benchmarks/jsframework/compare.roc 0.34.0   # the quick subset, to try the setup
```

The version is a tag or any commit that has `tests/apps/jsbench_keyed.roc`. The script:

1. Unpacks that version into `build/compare/<commit>/src` and builds its two benchmark
   apps there with `nix develop` of that tree, so with the compiler that version pins.
   Each side is then what its version ships. This step needs nix.
2. Prepares them exactly like the local entry (`wasm-opt -Oz`, the runtime through
   uglify) into `build/compare/<commit>/entries/`.
3. Copies them over the released entries in the clone (`frameworks/keyed/joy` and
   `frameworks/non-keyed/joy`) under the version's name, and keeps what was there in
   `build/compare/keep/`.
4. Runs `run.roc` once for each of `RUNS`. Every run is a normal run with its own
   report and its own row in the history.
5. Puts the released entries back, also when a run fails, and stops the benchmark
   server if it was the one to start it. A comparison that was killed leaves the entries
   swapped. The next `compare.roc` puts them back before it does anything else.
6. Pools the rounds of all the runs into one report,
   `runs/<timestamp>_vs_<version>/report.md`, and prints its comparison.

Before you start:

- Pin the governor (see above). The script checks it before it touches anything.
- Leave the machine alone for the whole time. No builds, no test suites, no second
  benchmark. Browser windows open and close on the display throughout.
- Three runs is the default because one is not enough to call a 2% change. The three
  runs of 2026-11-14 gave +2.6%, +2.5% and +1.9% for the same two builds.

Reading the result:

- Read the pooled table. A row says `slower` or `faster` only when its interval leaves
  out zero and every round moved the same way. Everything else is `noise`.
- The geomean repeats to about half a percent between runs. A single benchmark does
  not, least of all the ones the runner slows down (update, select, swap, clear).
- The instruction counts, the memory numbers and the bundle size are exact. A
  difference there is real whatever its size.
- When the two versions pin different compilers, the difference is the version's as a
  whole: its platform, its runtime and its compiler together.

## Finding where a difference comes from

The benchmark gives one number for a click. These say what is in it, the cheapest first.

**The instruction counts in the report.** Fewer wasm instructions and a longer time
means the time is not in Joy's hot code. Look at the browser next.

**The runner's own traces.** The runner keeps a Chrome trace of every measured click in
`webdriver-ts/traces/` of the clone, until the same entry and version is measured
again. `profile.mjs` splits them, with no browser:

```sh
node benchmarks/jsframework/profile.mjs traces $JS_FRAMEWORK_BENCHMARK_DIR/webdriver-ts/traces \
  04_select1k joy-dev-vd99a981.dirty-keyed joy-v0.34.0-keyed
```

**A profile of both builds in one session.** The traces of two entries can be half an
hour apart. `profile.mjs` measures the builds side by side instead, taking turns, the
way the runner measures: one browser for all the clicks of a build, a fresh page for
each click, the runner's warmups, a forced GC and its CPU slowdown. `compare.roc`
prints the command with the two entry folders filled in.

```sh
cd $JS_FRAMEWORK_BENCHMARK_DIR
direnv exec . node /path/to/joy/benchmarks/jsframework/profile.mjs \
  dev=frameworks/keyed/joy-dev earlier=/path/to/joy/build/compare/<commit>/entries/keyed
```

Without a dev shell in the clone, leave out `direnv exec .`. The columns:

| column | what it is |
|---|---|
| `total` | from the click to the end of the last commit, which is what the benchmark reports |
| `handler` | Joy's own share: the wasm and `runtime.js` the click ran |
| `UpdateLayoutTree`, `Layout`, `PrePaint`, `Paint`, `Layerize`, `Commit` | the browser's share, by stage |
| `forced` | style or layout inside the handler, which reading from the page forces |
| `styled` | how many elements the browser restyled |

If `styled` and the browser's stages are the same for both builds, the DOM work is the
same and the difference is in `handler`. Then these narrow it down:

- `--mode cpu` turns on V8's sampling profiler and lists the functions the handler was
  in, split into wasm, `runtime.js` and the browser. It slows every click a little, so
  take the totals from a run without it. The entries ship a minified runtime, so the
  names are short ones. For real names, copy an entry folder and put that version's
  `www/runtime.js` over its `dist/runtime.js`.
- `--benches selectwarm` measures the select click after forty other selects. A
  difference that is gone there was code running for the first time, not slower code.
- `--js-flags "--liftoff-only"` and `--js-flags "--no-liftoff"` pin the wasm to V8's
  baseline or its optimizing compiler, to see whether a difference is about which of
  the two the click happened to run on.
- `--benches` takes `create`, `update`, `select`, `selectwarm`, `swap`, `remove` and
  `clear`, and `--clicks` how many measured clicks each build gets (20).

What to keep in mind when reading any of it:

- Select row measures the second select the page ever makes, which is the first time
  the path that unselects a row runs. More code on that path costs there even when the
  same code is as fast once it is warm. On 2026-11-14 select row was 8 to 10% slower
  than 0.34.0 in the benchmark. The profile put it in the handler (1.19 ms against
  1.41 ms at the runner's slowdown) with the same 11 elements restyled, and after
  forty selects most of it was gone (0.63 ms against 0.69 ms).
- The browser keeps what it compiled of a page between loads, and the runner loads a
  page fifteen times or more in one browser. A profile that starts a new browser for
  every click measures something else: swap rows was 6.7% slower than 0.34.0 in the
  benchmark, level with a browser per click, and 4.5% slower once the profile kept its
  browsers open as the runner does. That is why `profile.mjs` keeps them open.
- Not every difference ends in a cause. Of that swap rows difference, about a third
  was in the handler and the rest in the browser's layout, for the same 1017 elements
  restyled and the same number laid out.
- The DOM calls in the report count a read like `parentOf` the same as a write, so a
  large change there can be cheap.
- The fake DOM in `tests/` checks itself after every paint (`checkNodes`), which a
  browser does not do and which takes most of a click's time there. Leave it out of
  the adapter before timing anything on the fake DOM.

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
