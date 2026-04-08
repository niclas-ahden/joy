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
    local app_name=$(basename "$app_dir")

    echo "Building test app: $app_name"

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
        JOY_PROJECT_ROOT=$project_root wasm-pack build --dev --target web --out-dir "$project_root/$www_dir/pkg/"
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
build_test_app "tests/apps/keyboard"

# ── Build test server ────────────────────────────────────────────────────

echo "Building test server..."
rm -f ./test-server
roc build tests/server/main.roc --output ./test-server --linker=legacy
echo "Build complete"
echo

# ── Unit tests (roc test) ────────────────────────────────────────────────

echo "Running unit tests..."
roc test platform/Action.roc
roc test platform/Url.roc
echo

# ── Browser tests (roc-playwright) ──────────────────────────────────────

echo "Running browser tests..."
run_scoped roc dev tests/run.roc --linker=legacy -- "$@"
