# Joy

A framework for building full-stack web apps in Roc!

Joy is a jolt of happiness for those who want a fast, productive, fun, and statically-typed environment for full-stack development.

It's a fork of Luke Boswell's awesome [Roc Experiment JS DOM](https://github.com/lukewilliamboswell/roc-experiment-js-dom) which opened up the avenue for me to use Roc on the front-end. Thank you Luke!

## Goals

Joy should provide:
* A convenient way of writing apps that run on the server and client (sometimes called "isomorphic" apps)
* A convenient way of communicating between the front- and back-end (perhaps [Server Functions](https://book.leptos.dev/server/25_server_functions.html), or message-passing over websockets, or ...)
* Geat developer experience (feedback, iteration time, tooling, etc.)
* Great performance for the vast majority of apps, but not at any cost (in line with Roc's philosophy of aiming for Go's performance rather than Rust's)

## Status

Joy is fun to play with, but it's in early development, not production-ready, is missing most of its intended features,
and will change a lot. Even the underpinning technologies are not production-ready ([Roc](https://www.roc-lang.org),
[`percy-dom`](https://github.com/chinedufn/percy)). Here be dragons!

You can currently build a small Elm-like front-end application in it (see the [examples](https://github.com/niclas-ahden/joy/tree/main/examples)). You can build a separate back-end using [`roc-lang/basic-webserver`](https://github.com/roc-lang/basic-webserver) for a full-stack experience. Hopefully, Joy will offer a seamless bridge between your front- and back-end in the future, but for now just start two separate projects and enjoy Roc!

## Example

A client-side counter:

```roc
app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, button, text]
import web.Action exposing [Action]

Model : I64

init! : {} => Model
init! = \{} -> 0

Event : [
    UserClickedDecrement,
    UserClickedIncrement,
]

update! : Model, Str, Str => Action Model
update! = \model, raw, _ ->
    when decodeEvent raw is
        UserClickedDecrement -> Num.subWrap model 1 |> Action.update
        UserClickedIncrement -> Num.addWrap model 1 |> Action.update

render : Model -> Html Model
render = \model ->
    div [] [
        button [] [{ name: "onclick", handler: encodeEvent UserClickedIncrement }] [text "+"],
        text (Inspect.toStr model),
        button [] [{ name: "onclick", handler: encodeEvent UserClickedDecrement }] [text "-"],
    ]

encodeEvent : Event -> Str
encodeEvent = \event -> Inspect.toStr event

decodeEvent : Str -> Event
decodeEvent = \raw ->
    when raw is
        "UserClickedIncrement" -> UserClickedIncrement
        "UserClickedDecrement" -> UserClickedDecrement
        _ -> crash "Unsupported event type \"$(raw)\""
```

[See more examples](https://github.com/niclas-ahden/joy/tree/main/examples)

## Try it out

You can try out one of the examples and start modifying it to get going.

Use the included Nix flake or install these dependencies:

Required:
* [`roc`](https://www.roc-lang.org/install) (tested with commit `50ec8ef1d1aa9abb2fda6948fb13abb431940ddf`)
* `zig 13`
* `rustc`
* `cargo`
* `lld`
* [`wasm-pack`](https://rustwasm.github.io/wasm-pack/installer/)

Recommended:
* `rustfmt`
* `rust-analyzer`
* `simple-http-server`
* `inotify-tools` (on Linux)
* `watchexec`

### Watch

Install `watchexec`, `inotify-tools` (on Linux), and `simple-http-server`, then:

```sh
$ ./watch.sh examples/hello.roc
```
The application should now be available at: [`http://localhost:3000`](http://localhost:3000). Your Roc application and the platform will be recompiled on change, but there's no hot-reloading in the browser. Refresh the page to see changes.

### Deploying an app

Delete existing assets then build for release:

```sh
$ rm -rf ./www/pkg
$ ./build.sh --release examples/hello.roc
```

You'll end up with a complete front-end app in the `www` directory. You can deploy that anywhere as you see fit. There's no way to bundle it with a back-end yet.

## Contributing

Contributions are very welcome, including feature requests, design discussion, etc.

## Development setup

Do everything under "Try it out" and you're golden.

### CLI

Using WASI to debug the Roc FFI without the complications of `wasm-pack` and the browser.

Install [`bytecodealliance/cargo-wasi`](https://github.com/bytecodealliance/cargo-wasi), then:

```sh
$ ./run-cli.sh examples/hello.roc
```

## Sponsors

Joy is sponsored by the real estate agency [BOSTHLM Fastighetsmäklare](https://www.bosthlm.se) which thrives by using technology to bolster its agents and business. Thank you!

Have a look at their search feature on [www.bosthlm.se/till-salu](https://www.bosthlm.se/till-salu) which is a front-end application written in Roc.
