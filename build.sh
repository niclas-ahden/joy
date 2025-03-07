#!/usr/bin/env bash
set -euo pipefail

# --dev, --profiling, --release
profile=$1
app=$2

# Delete potential build remnants
rm -f app.o
rm -f libapp.a

echo "====> Roc build"
# Continue despite warnings (`roc` exits with code 2 on warnings)
exit_code=0
roc build --target wasm32 --no-link --emit-llvm-ir --output app.o $app || exit_code=$?

if [ "${exit_code}" -eq 0 ] || [ "${exit_code}" -eq 2 ]; then
  echo "====> Zig build"
  zig build-lib -target wasm32-freestanding-musl --library c app.o
  project_root=$(pwd)
  cd crates/web/
  echo "====> wasm-pack"
  JOY_PROJECT_ROOT=$project_root wasm-pack build $profile --target web --out-dir ../../www/pkg/
  cd ../../
else
  exit $exit_code
fi
