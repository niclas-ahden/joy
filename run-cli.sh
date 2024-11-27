#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

rm -f app.o
rm -f libapp.a

roc check $1
roc build --target wasm32 --no-link --emit-llvm-ir --output app.o $1
zig build-lib -target wasm32-freestanding-musl -lc app.o

cargo wasi run -p cli
