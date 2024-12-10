#!/usr/bin/env bash
set -euo pipefail

# --dev, --profiling, --release
profile=$1
app=$2

rm -f app.o
rm -f libapp.a

# Continue despite warnings (`roc` exits with code 2 on warnings)
exit_code=0
roc check $app || exit_code=$?
if [ "${exit_code}" -eq 0 ] || [ "${exit_code}" -eq 2 ]; then
  roc build --target wasm32 --no-link --emit-llvm-ir --output app.o $app || true
  zig build-lib -target wasm32-freestanding-musl -lc app.o
  cd crates/web/
  wasm-pack build $profile --target web --out-dir ../../www/pkg/
  cd ../../
else
  exit 1
fi
