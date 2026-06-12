# Performance regression benchmarks

Joy has two complementary performance suites. Both are **local tools**: you run them by
hand and compare against a saved baseline, the same way `cargo bench --baseline` works.
There is no CI gate (a noisy shared runner makes vdom timings unreliable anyway).

The split mirrors who owns each layer:

| Suite | Measures | Lives in |
|-------|----------|----------|
| **Joy end-to-end** (this dir) | the full update cycle Joy owns: Roc `render` → `roc_html_to_percy` → percy diff+patch, in a real browser | here |
| **percy `diff`** | the virtual-DOM diff algorithm in isolation | the [percy fork](https://github.com/niclas-ahden/percy), `crates/percy-dom/benches/diff.rs` |

If a number moves, this tells you *which* layer moved: a `render`/`convert` regression is
Joy's (the Roc app or the glue in `crates/web/src/lib.rs`); a `diff_patch` regression is
most likely percy's, and the percy benches will localize it further.

## Joy end-to-end

```sh
tests/bench/bench.sh                  # run and compare against baseline.json
tests/bench/bench.sh --save-baseline  # accept the current numbers as the new baseline
```

It builds the bench app (`tests/apps/bench`) with the `joy_bench` cargo feature, serves
it, and drives many `step` events in headless Chromium. The `joy_bench` instrumentation
(`crates/web/src/bench.rs`) times each update's three phases with `performance.now()` and
appends them to `window.__joy_bench`; the driver (`driver.roc`) collects them and the
script reports per-phase medians:

- **render** — Roc executes the app's `render`
- **convert** — `roc_html_to_percy` turns Roc html into a percy `VirtualNode`
- **diff_patch** — percy diffs against the live tree and patches the real DOM

Tunables (env): `BENCH_STEPS` (default 200), `BENCH_WARMUP` (default 30), `BENCH_PORT`
(default 8080), `BENCH_THRESHOLD` (slowdown ratio that prints `⚠ REGRESSION`, default 1.10).

`performance.now()` is deliberately coarsened by browsers, so treat single-digit-percent
moves as noise — re-run before trusting a regression, and prefer larger `BENCH_STEPS` when
chasing a small one. The instrumentation is compiled out entirely without `joy_bench`, so
normal builds pay nothing.

## percy `diff`

In the percy fork:

```sh
cargo bench -p percy-dom --bench diff -- --save-baseline main   # establish baseline
cargo bench -p percy-dom --bench diff -- --baseline main        # compare after a change
```

These are native Criterion benchmarks (no browser) over representative `VirtualNode`
scenarios: create/remove 1000 rows, no-op, update-all-text, sparse update, append.
`patch` is not benchmarked there because applying patches needs a real DOM — that path is
covered end-to-end by the Joy suite above.
