# VDOM tests

Engine-agnostic regression tests for Joy's virtual-DOM contract — `Model → render → diff
→ patch → real DOM` (and per-row events). They assert against **Joy's own DOM output**, not
percy internals, so they stay valid if percy is ever replaced; they'd be the acceptance
suite a replacement must pass. (percy keeps its own fast native diff tests for localizing
bugs while Joy uses it; those are percy's concern and disposable from Joy's side.)

## `fuzz.roc` — model-based diff fuzz

Keeps a "shadow" model in the driver, applies a random sequence of structural ops
(append / insert / remove / swap / update-label / toggle-selected / clear), pushes each
resulting state into the app (`tests/apps/vdom`, which exercises the diff), and asserts
the live DOM matches the shadow after **every** step. A mismatch means the incremental
diff/patch diverged from the true model — a real bug.

Rows carry an `onclick`, so event-listener add/remove is exercised on every
insert/remove — the path most likely to regress (and where a memory leak once lived).

Run (needs `tests/apps/vdom` built and the test server serving it):

```sh
# part of the suite:
./tests.sh                              # runs the fuzz (FUZZ_ITERS=300, FUZZ_SEED=1) + browser tests

# standalone, heavier / specific seed:
ROC_BASIC_WEBSERVER_PORT=8090 ./test-server &
VDOM_URL=http://localhost:8090 FUZZ_ITERS=1000 FUZZ_SEED=42 roc dev tests/vdom/fuzz.roc --linker=legacy
```

**Reproducing a failure:** the run prints its `seed`. Re-run with that `FUZZ_SEED` (and
`FUZZ_ITERS`) to get the identical op sequence; the mismatch prints the step number and
the expected vs actual table contents.

The fuzz also fires **real events**: with some probability each step clicks a random row's
`onclick` (instead of pushing a state) and asserts the *correct* row toggled — so it proves
handlers don't just attach but **dispatch correctly after arbitrary diffs** (the failure
mode of a stale/mis-bound handler after a reorder/remove).

## `leak.roc` — memory-leak guard

Repeatedly creates a 1,000-row list and clears it, watching the WASM linear-memory size
(`window.__joy_wasm_bytes`, exposed by the app) after each cycle. WASM memory only grows,
so a steady per-cycle increase = memory not reclaimed on clear (a leak). Asserts a per-cycle
growth threshold, so it **fails while the leak exists and passes once fixed** — a guard for
the event-teardown work.

```sh
VDOM_URL=http://localhost:8090 LEAK_MAX_GROWTH_KB=512 roc dev tests/vdom/leak.roc --linker=legacy
```

It reads the raw WASM heap, so (unlike the benchmark's `measureUserAgentSpecificMemory`) it
needs no cross-origin-isolation headers. It is **currently RED** (~900 KB/cycle leak); once
#2 is fixed it should pass and be wired into `tests.sh` as a fatal check.

## Ideas / follow-ups

- Add explicit example tests (named scenarios: insert-middle, swap-ends, etc.) for
  readability alongside the fuzz.
- Cover keyed lists if/when percy/Joy gains keys.
- Shrinking: on failure, automatically minimize the op sequence (the seed gives
  reproducibility today; minimization would speed debugging).
