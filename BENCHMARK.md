# Benchmarking Joy

Joy's performance is tracked against [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark),
with comparisons against vanilla JS, Elm (keyed + non-keyed), Leptos, and React.

There are two complementary layers; see also `benchmarks/jsframework/README.md` and
`tests/bench/README.md`.

| Layer | What it measures | Where |
|-------|------------------|-------|
| **Cross-framework** (this doc) | Joy vs other frameworks: CPU (create/update/select/swap/remove/clear), memory, bundle size | `benchmarks/jsframework/` |
| **End-to-end phases** | Joy's own update cycle split into render → convert → diff+patch | `tests/bench/` (the `joy_bench` cargo feature) |
| **percy diff** | the virtual-DOM diff algorithm in isolation | the [percy fork](https://github.com/niclas-ahden/percy), `crates/percy-dom/benches/diff.rs` |

## One-time setup

The cross-framework benchmark lives in a local clone of
[our js-framework-benchmark fork](https://github.com/niclas-ahden/js-framework-benchmark)
(branch `joy`, which carries the Joy entry and a nix dev shell on top of upstream).
Clone it wherever you like and point `JS_FRAMEWORK_BENCHMARK_DIR` at it in this repo's
`.envrc` (`.envrc` is not tracked):

```sh
git clone -b joy git@github.com:niclas-ahden/js-framework-benchmark
```

```sh
# in joy/.envrc
export JS_FRAMEWORK_BENCHMARK_DIR="$HOME/dev/js-framework-benchmark"
export PERCY_DIR="$HOME/dev/percy"
```

`PERCY_DIR` points at your clone of the [percy fork](https://github.com/niclas-ahden/percy);
it is only used to record the percy commit in each history row (the build pulls percy
from the git dependency in `crates/web/Cargo.toml`).

The clone has its own nix dev shell (`flake.nix`) providing node/npm, the Joy build
toolchain (roc/zig/wasm-pack), and Playwright browsers. Set it up once:

```sh
cd "$JS_FRAMEWORK_BENCHMARK_DIR"
direnv allow                       # activate the dev shell
npm ci && npm run install-local    # install the server + webdriver-ts runner
# comparison entries: keyed/leptos is prebuilt; build the others once:
( cd frameworks/keyed/react-hooks && npm install && npm run build-prod )
( cd frameworks/keyed/elm     && npm install --ignore-scripts && npm run build-prod )
( cd frameworks/non-keyed/elm && npm install --ignore-scripts && npm run build-prod )
```

Joy itself is the `frameworks/non-keyed/joy` entry; `run.sh` rebuilds it from this repo
each time, so you don't build it manually.

## Running

From this repo:

```sh
benchmarks/jsframework/run.sh          # Joy only (CPU+memory+size); ~6x faster — the default for iterating
FULL=1 benchmarks/jsframework/run.sh   # also re-run the comparison frameworks (milestone / version refresh)
FAST=1 benchmarks/jsframework/run.sh   # Joy only, quick: create / swap / remove only
```

**By default only Joy is re-benchmarked.** The comparison frameworks don't change between
Joy edits, so their result JSONs from the last `FULL` run are reused by the renderer — you
still get the full comparison table, but in ~7 min instead of ~45. Use `FULL=1` for a
milestone snapshot or after updating a competitor's version (this is also the run that
*establishes* the competitor numbers the default mode reuses, so run it at least once).

Each run:
1. rebuilds the Joy entry from the current checkout (records the git + percy commits),
2. runs in headed Chromium (**windows will flash on your display — expected**), 15 samples per CPU benchmark,
3. writes a dated snapshot and appends to the history.

## Output

- `benchmarks/jsframework/runs/<timestamp>/report.md` — full cross-framework tables (CPU, memory, bundle size) for that run, plus Joy's CPU geomean and slowdown-vs-best.
- `benchmarks/jsframework/runs/<timestamp>/results/` — raw result JSONs.
- `benchmarks/jsframework/HISTORY.md` + `history.jsonl` — one row per run of Joy's headline numbers (commit, CPU geomean, slowdown, memory, bundle), so improvement/regression over time is visible at a glance.

**Workflow for an optimization:** note the current `HISTORY.md` numbers → make the change
→ `benchmarks/jsframework/run.sh` → compare the new row. Commit the snapshot so the
history is versioned.

## Notes / caveats

- Runs are **headed** (the benchmark's default, for timing accuracy). The runner launches Chrome via `--chromeBinary`; `run.sh` points it at the nix chromium under `$PLAYWRIGHT_BROWSERS_PATH`.
- The lighthouse `30_startup` benchmark is **not** run (needs extra Chrome wiring); CPU, memory, and bundle size are.
- `07_create10k` is run unbatched with a single sample: batched runs bleed warmup mousedown events into the trace and the runner rejects every sample after the first.
- Numbers are machine- and load-dependent; compare runs from the same machine and treat single-digit-percent moves as noise.
