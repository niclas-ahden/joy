#!/usr/bin/env bash
# Run the js-framework-benchmark suite for Joy + the comparison frameworks and write a
# dated snapshot under runs/<timestamp>/, appending to history.jsonl / HISTORY.md.
#
# This is how we track Joy's performance over time: make a change in the Joy repo, then
# run this to see the new numbers next to the previous runs.
#
# Usage:
#   benchmarks/jsframework/run.sh                 # full CPU+MEM+SIZE suite
#   FAST=1 benchmarks/jsframework/run.sh          # quick subset (run/swap/remove) for a sanity check
#
# JS_FRAMEWORK_BENCHMARK_DIR must point at your js-framework-benchmark clone (set it in .envrc; see
# BENCHMARK.md for the one-time setup). The clone's dev shell provides node/npm +
# roc/zig/wasm-pack + Playwright browsers; the script wraps its work in `direnv exec`,
# so run it from anywhere as long as that repo has been `direnv allow`ed.
set -eo pipefail

JOY_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
JS_FRAMEWORK_BENCHMARK_DIR=${JS_FRAMEWORK_BENCHMARK_DIR:?JS_FRAMEWORK_BENCHMARK_DIR is not set. Point it at your js-framework-benchmark clone (see BENCHMARK.md).}
HERE="$JOY_REPO/benchmarks/jsframework"

# By default we only re-benchmark Joy: the comparison frameworks don't change between Joy
# edits, and their result JSONs from the last full run stay in webdriver-ts/results/, which
# the renderer reuses -- so the report is still a full comparison table, ~6x faster.
# Set FULL=1 to also re-run the comparison frameworks (do this for a milestone snapshot, or
# after updating their versions). They must have been built at least once (see README).
if [ -n "$FULL" ]; then
  FRAMEWORKS="non-keyed/joy non-keyed/vanillajs keyed/elm non-keyed/elm keyed/leptos keyed/react-hooks"
else
  FRAMEWORKS="non-keyed/joy"
fi
if [ -n "$FAST" ]; then
  BENCHES="01_ 05_ 06_"
else
  # 07_create10k is NOT here: batched runs bleed warmup mousedowns into the trace and the
  # runner rejects every sample after the first (hits all frameworks on this setup). It
  # gets its own unbatched --count 1 pass below.
  BENCHES="01_ 02_ 03_ 04_ 05_ 06_ 08_ 09_ 21_ 22_ 23_ 24_ 25_ 26_ 40_"
fi

# Only used to record the percy commit in the history row (the build itself pulls percy
# from the git dependency in crates/web/Cargo.toml, or from your path override).
PERCY_DIR=${PERCY_DIR:?PERCY_DIR is not set. Point it at your percy clone (see BENCHMARK.md).}
stamp=$(date '+%Y-%m-%d_%H%M')
label=$(date '+%Y-%m-%d %H:%M %Z')
commit=$(git -C "$JOY_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
subject=$(git -C "$JOY_REPO" log -1 --format='%s' 2>/dev/null || echo "")
percy_commit=$(git -C "$PERCY_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
if [ -n "$FULL" ]; then note=""; else note="Only Joy was re-measured this run; comparison frameworks are reused from the last full run (FULL=1 to refresh them)."; fi
out="$HERE/runs/$stamp"

direnv exec "$JS_FRAMEWORK_BENCHMARK_DIR" bash -c "
  set -eo pipefail
  CHROME=\$(ls -d \"\$PLAYWRIGHT_BROWSERS_PATH\"/chromium-*/chrome-linux64/chrome | head -1)
  chromium_ver=\$(basename \"\$(dirname \"\$(dirname \"\$CHROME\")\")\")

  echo '== rebuilding Joy entry =='
  ( cd '$JS_FRAMEWORK_BENCHMARK_DIR/frameworks/non-keyed/joy' && JOY_ROOT='$JOY_REPO' ./build.sh )

  echo '== ensuring server =='
  if ! (exec 3<>/dev/tcp/localhost/8080) 2>/dev/null; then
    ( cd '$JS_FRAMEWORK_BENCHMARK_DIR' && npm start >/tmp/jsfb-server.log 2>&1 & )
    for _ in \$(seq 1 50); do (exec 3<>/dev/tcp/localhost/8080) 2>/dev/null && break; sleep 0.2; done
  fi

  echo '== running benchmarks: $BENCHES =='
  # Stale-result hygiene: per-bench JSONs survive failed re-measures and would get folded
  # into the new report as if current. Delete Joy's results so the report only contains
  # what this run actually measured.
  rm -f '$JS_FRAMEWORK_BENCHMARK_DIR/webdriver-ts/results/'joy-*.json
  # A single benchmark failing for one framework makes the runner exit non-zero; tolerate
  # it so the remaining results still render.
  ( cd '$JS_FRAMEWORK_BENCHMARK_DIR/webdriver-ts' && npm run bench -- --framework $FRAMEWORKS --benchmark $BENCHES --chromeBinary \"\$CHROME\" ) || echo '(benchmark reported errors; rendering available results)'

  if [ -z '$FAST' ]; then
    echo '== running create10k unbatched (single sample; batching bleeds traces) =='
    ( cd '$JS_FRAMEWORK_BENCHMARK_DIR/webdriver-ts' && npm run bench -- --framework $FRAMEWORKS --benchmark 07_ --count 1 --chromeBinary \"\$CHROME\" ) || echo '(create10k failed; it will render as —)'
  fi

  echo '== rendering report =='
  node '$HERE/render.mjs' \
    --results '$JS_FRAMEWORK_BENCHMARK_DIR/webdriver-ts/results' \
    --out '$out' \
    --label '$label' --commit '$commit' --subject '$subject' \
    --percy-commit '$percy_commit' --note '$note' \
    --chromium \"\${chromium_ver#chromium-}\"
"

# Keep a copy of the raw result JSONs alongside the report for full reproducibility.
mkdir -p "$out/results"
cp "$JS_FRAMEWORK_BENCHMARK_DIR"/webdriver-ts/results/*.json "$out/results/" 2>/dev/null || true

echo
echo "Snapshot written to $out/report.md"
echo "History: $HERE/HISTORY.md"
