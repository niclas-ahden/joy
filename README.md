# Roc Experiment JS DOM

This is a small experiment to show how to use Roc and Rust to build manipulate the DOM in a web page via wasm-pack.

**NOTE** tested on apple silicon macOS, probably just works on other systems. If you test it on something else, let me know.

## DEMO

Here is a demo to save you building from source.

![demo](/demo.gif)

## WEB

- install [rustwasm.github.io/wasm-pack](https://rustwasm.github.io/wasm-pack/installer/)

```sh
$ ./run-web.sh examples/hello.roc
```

## CLI

I added a cli using WASI to help debug the roc FFI without the complications of wasm-pack and the browser.

- install `cargo install cargo-wasi` see [bytecodealliance/cargo-wasi](https://github.com/bytecodealliance/cargo-wasi)

```sh
$ ./run-cli.sh examples/hello.roc
```
