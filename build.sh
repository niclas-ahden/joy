#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc build --target wasm32 --no-link --output app.o $1
zig build-lib -target wasm32-freestanding-musl -lc app.o
wasm-pack build --target web --out-dir www/pkg/
simple-http-server --ip 127.0.0.1 --index --open -- www/
