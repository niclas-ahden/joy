#!/usr/bin/env bash
set -eo pipefail

cd "$(dirname "$0")"

# ── Scoped process cleanup ───────────────────────────────────────────────
SCOPE_MARKER="/tmp/joy_test_scope"

if [[ "$(uname)" == "Darwin" ]]; then
    run_scoped() {
        if [[ -f "$SCOPE_MARKER" ]]; then
            lsof -t "$SCOPE_MARKER" 2>/dev/null | xargs kill 2>/dev/null || true
            sleep 0.1
        fi
        touch "$SCOPE_MARKER"

        "$@" 3< "$SCOPE_MARKER" &
        local pid=$!
        trap "lsof -t '$SCOPE_MARKER' 2>/dev/null | xargs kill 2>/dev/null || true; rm -f '$SCOPE_MARKER'; exit 130" INT TERM

        local status=0
        wait $pid || status=$?

        lsof -t "$SCOPE_MARKER" 2>/dev/null | xargs kill 2>/dev/null || true
        sleep 0.1
        lsof -t "$SCOPE_MARKER" 2>/dev/null | xargs kill -9 2>/dev/null || true

        rm -f "$SCOPE_MARKER"
        trap - INT TERM
        return $status
    }
elif systemctl --user show-environment &>/dev/null; then
    run_scoped() {
        systemd-run --scope --user "$@"
    }
else
    run_scoped() {
        "$@"
    }
fi

# ── Build test apps (WASM) ───────────────────────────────────────────────

build_test_app() {
    local app_dir="$1"
    local profile="${2:---dev}"
    local app_name=$(basename "$app_dir")

    echo "Building test app: $app_name ($profile)"

    local www_dir="$app_dir/www"
    rm -rf "$www_dir"
    rm -f app.o libapp.a

    exit_code=0
    roc build --target wasm32 --no-link --emit-llvm-ir --output app.o "$app_dir/main.roc" || exit_code=$?

    if [ "${exit_code}" -eq 0 ] || [ "${exit_code}" -eq 2 ]; then
        zig build-lib -target wasm32-freestanding-musl --library c app.o

        project_root=$(pwd)
        mkdir -p "$www_dir/pkg"
        cd crates/web/
        JOY_PROJECT_ROOT=$project_root wasm-pack build "$profile" --target web --out-dir "$project_root/$www_dir/pkg/"
        cd "$project_root"

        cp "$app_dir/index.html" "$www_dir/index.html"
    else
        exit $exit_code
    fi

    rm -f app.o libapp.a
}

build_test_app "tests/apps/crypto"
build_test_app "tests/apps/http"
build_test_app "tests/apps/time"
build_test_app "tests/apps/dom"
build_test_app "tests/apps/vdom"
build_test_app "tests/apps/keyboard"

# ── Build test server ────────────────────────────────────────────────────

echo "Building test server..."
rm -f ./test-server
roc build tests/server/main.roc --output ./test-server --linker=legacy
echo "Build complete"
echo

# ── Feature builds (compile-only) ────────────────────────────────────────

# The joy_bench instrumentation is only built by tests/bench/bench.sh, so a green suite
# would not otherwise notice when the feature stops compiling.
echo "Checking the joy_bench build..."
JOY_PROJECT_ROOT=$(pwd) cargo check -p web --target wasm32-unknown-unknown --features joy_bench
echo

# ── Unit tests (roc test) ────────────────────────────────────────────────

echo "Running unit tests..."
roc test platform/Action.roc
roc test platform/Url.roc
echo

# ── VDOM fuzz (model-based diff/render/patch property) ──────────────────

echo "Running vdom fuzz..."
ROC_BASIC_WEBSERVER_PORT=8090 ./test-server &
vdom_srv=$!
trap "kill $vdom_srv 2>/dev/null || true" EXIT
for _ in $(seq 1 50); do (exec 3<>/dev/tcp/localhost/8090) 2>/dev/null && { exec 3>&- 3<&-; break; }; sleep 0.2; done
VDOM_URL=http://localhost:8090 FUZZ_ITERS="${FUZZ_ITERS:-300}" FUZZ_SEED="${FUZZ_SEED:-1}" \
    roc dev tests/vdom/fuzz.roc --linker=legacy
# Seed 7 reaches the historical allocator-corruption/UAF repro (a set: state whose labels
# are seamless slices into the event buffer, then a toggle — step 39); seed 1 never does.
# Any allocator/glue refcount regression should trip here.
VDOM_URL=http://localhost:8090 FUZZ_ITERS=100 FUZZ_SEED=7 \
    roc dev tests/vdom/fuzz.roc --linker=legacy

echo "Running vdom leak guard..."
# Fatal: heap growth per create/clear cycle must stay in the tens of KB (the leak fix
# landed at ~36 KB/cycle; the leak was ~5 MB/cycle). set -e makes a failure abort the suite.
VDOM_URL=http://localhost:8090 LEAK_MAX_GROWTH_KB="${LEAK_MAX_GROWTH_KB:-512}" \
    roc dev tests/vdom/leak.roc --linker=legacy

# ── VDOM fuzz + leak guard against the release build ─────────────────────

# Release optimization (opt-level=z + LTO + wasm-opt -Oz) can surface bugs that dev
# builds hide, and the dev build's debug assertions compile out in release. Rebuild the
# vdom app with the shipped profile and run the same gates at full size.
build_test_app "tests/apps/vdom" --release

echo "Running vdom fuzz (release)..."
VDOM_URL=http://localhost:8090 FUZZ_ITERS="${FUZZ_ITERS:-300}" FUZZ_SEED="${FUZZ_SEED:-1}" \
    roc dev tests/vdom/fuzz.roc --linker=legacy
VDOM_URL=http://localhost:8090 FUZZ_ITERS=100 FUZZ_SEED=7 \
    roc dev tests/vdom/fuzz.roc --linker=legacy

echo "Running vdom leak guard (release)..."
VDOM_URL=http://localhost:8090 LEAK_MAX_GROWTH_KB="${LEAK_MAX_GROWTH_KB:-512}" \
    roc dev tests/vdom/leak.roc --linker=legacy

kill $vdom_srv 2>/dev/null || true
trap - EXIT
echo

# ── Browser tests (roc-playwright) ──────────────────────────────────────

echo "Running browser tests..."
run_scoped roc dev tests/run.roc --linker=legacy -- "$@"
