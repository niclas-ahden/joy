# Roc Experiment JS DOM

**NOTE** tested on apple silicon macOS, needs minor changes to work on other systems.

Install [rustwasm.github.io/wasm-pack](https://rustwasm.github.io/wasm-pack/installer/)

```
$ roc build --target wasm32 --no-link --output app.o examples/hello.roc
$ zig build-lib -target wasm32-freestanding-musl -lc app.o
$ wasm-pack build --target web --out-dir www/pkg/
$ simple-http-server --ip 127.0.0.1 --index --open -- www/
```
