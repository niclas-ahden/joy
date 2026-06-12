#!/usr/bin/env bash
# End-to-end performance benchmark for Joy's update cycle.
#
# Builds the bench app (tests/apps/bench) with the `joy_bench` instrumentation feature,
# serves it, drives many update cycles in a headless browser, and reports the median
# cost of each phase (render / convert / diff_patch) in milliseconds.
#
# Usage:
#   tests/bench/bench.sh                  # run and compare against the saved baseline
#   tests/bench/bench.sh --save-baseline  # run and overwrite the baseline with this run
#
# Tunables (env): BENCH_PORT (default 8080), BENCH_STEPS (default 200).
#
# This is intentionally a *local* tool: it has no CI gate. Compare runs by hand the way
# you would with `cargo bench --baseline` for the percy-side diff benchmarks.
set -eo pipefail

cd "$(dirname "$0")/../.."
repo_root=$(pwd)

SAVE_BASELINE=0
[[ "${1:-}" == "--save-baseline" ]] && SAVE_BASELINE=1

PORT=${BENCH_PORT:-8080}
STEPS=${BENCH_STEPS:-200}
BASELINE="tests/bench/baseline.json"
# Threshold (as a ratio) above which a slowdown is flagged. Informational only.
THRESHOLD=${BENCH_THRESHOLD:-1.10}

# ── Build the bench app (WASM) with the joy_bench feature ────────────────
echo "Building bench app (joy_bench feature)..."
app_dir="tests/apps/bench"
www_dir="$app_dir/www"
rm -rf "$www_dir"
rm -f app.o libapp.a

exit_code=0
roc build --target wasm32 --no-link --emit-llvm-ir --output app.o "$app_dir/main.roc" || exit_code=$?
if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 2 ]; then
    exit $exit_code
fi

zig build-lib -target wasm32-freestanding-musl --library c app.o
mkdir -p "$www_dir/pkg"
(
    cd crates/web/
    JOY_PROJECT_ROOT="$repo_root" wasm-pack build --dev --target web \
        --out-dir "$repo_root/$www_dir/pkg/" -- --features joy_bench
)
cp "$app_dir/index.html" "$www_dir/index.html"
rm -f app.o libapp.a

# ── Build + start the static test server ─────────────────────────────────
if [ ! -x ./test-server ]; then
    echo "Building test server..."
    roc build tests/server/main.roc --output ./test-server --linker=legacy
fi

echo "Starting server on port $PORT..."
ROC_BASIC_WEBSERVER_PORT="$PORT" ./test-server &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

# Wait for the server to accept connections.
for _ in $(seq 1 100); do
    if (exec 3<>"/dev/tcp/localhost/$PORT") 2>/dev/null; then
        exec 3>&- 3<&-
        break
    fi
    sleep 0.1
done

# ── Drive the browser and collect raw per-update samples ─────────────────
echo "Running $STEPS update cycles..."
driver_out=$(BENCH_URL="http://localhost:$PORT" BENCH_STEPS="$STEPS" \
    roc dev tests/bench/driver.roc --linker=legacy)

samples=$(printf '%s\n' "$driver_out" | sed -n 's/^JOY_BENCH_RESULT //p')
if [ -z "$samples" ]; then
    echo "ERROR: driver produced no JOY_BENCH_RESULT line. Output was:" >&2
    printf '%s\n' "$driver_out" >&2
    exit 1
fi

# ── Reduce to medians ────────────────────────────────────────────────────
current=$(printf '%s' "$samples" | jq -c '
    def med(f): (map(f) | sort) as $s | $s[(($s | length) / 2) | floor];
    def r3: (. * 1000 | round) / 1000;   # round to 3 decimals (perf.now() is coarse anyway)
    { render: (med(.render) | r3), convert: (med(.convert) | r3),
      diff_patch: (med(.diff_patch) | r3), total: (med(.render + .convert + .diff_patch) | r3),
      samples: length }')

echo
echo "Median per-update timings (ms):"
printf '%s\n' "$current" | jq .

# ── Save or compare ──────────────────────────────────────────────────────
if [ "$SAVE_BASELINE" -eq 1 ]; then
    printf '%s\n' "$current" | jq . > "$BASELINE"
    echo
    echo "Saved baseline to $BASELINE"
    exit 0
fi

if [ ! -f "$BASELINE" ]; then
    echo
    echo "No baseline at $BASELINE. Run: tests/bench/bench.sh --save-baseline"
    exit 0
fi

echo
echo "vs baseline ($BASELINE):"
jq -n --argjson cur "$current" --slurpfile base "$BASELINE" --argjson thr "$THRESHOLD" '
    $base[0] as $b
    | ["render","convert","diff_patch","total"][]
    | . as $k
    | ($cur[$k]) as $c | ($b[$k]) as $base_v
    | (if $base_v > 0 then $c / $base_v else 1 end) as $ratio
    | "  \($k): \($c)ms  (baseline \($base_v)ms, \(((($ratio - 1) * 1000) | round / 10))%)"
      + (if $ratio > $thr then "  ⚠ REGRESSION" else "" end)' -r
