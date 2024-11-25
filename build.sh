#!/bin/bash

roc build --target wasm32 --no-link --output app.o examples/hello.roc
zig build-lib -target wasm32-freestanding-musl -lc app.o
wasm-pack build --target web --out-dir www/pkg/
simple-http-server --ip 127.0.0.1 --index --open -- www/
