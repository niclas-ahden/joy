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

Joy is fun to play with, but it's in early development, not production-ready, is missing most of its intended features, and will change a lot. Even the underpinning technologies are not production-ready ([Roc](https://www.roc-lang.org), [`percy-dom`](https://github.com/chinedufn/percy)). Here be dragons!

You can already build full-stack or single-page applications in it but the functionality is severely limited. Have a look at the [examples](https://github.com/niclas-ahden/joy/tree/main/examples) to get a grasp on what's currently supported.

Have fun and expect breaking changes!

## Example

A client-side counter:

```roc
app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.1.0/g0btWTwHYXQ6ZTCsMRHnCxYuu73bZ5lharzD_p1s5lE.tar.br",
}

import html.Html exposing [Html, div, button, text]
import pf.Action exposing [Action]

Model : I64

init! : Str => Model
init! = |_flags| 0

Event : [
    UserClickedDecrement,
    UserClickedIncrement,
]

update! : Model, Str, Str => Action Model
update! = |model, raw, _payload|
    when decode_event(raw) is
        UserClickedDecrement -> Num.sub_wrap(model, 1) |> Action.update
        UserClickedIncrement -> Num.add_wrap(model, 1) |> Action.update

render : Model -> Html Model
render = |model|
    div(
        [],
        [
            button([], [{ name: "onclick", handler: encode_event(UserClickedIncrement) }], [text("+")]),
            text(Inspect.to_str(model)),
            button([], [{ name: "onclick", handler: encode_event(UserClickedDecrement) }], [text("-")]),
        ],
    )

encode_event : Event -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str -> Event
decode_event = |raw|
    when raw is
        "UserClickedIncrement" -> UserClickedIncrement
        "UserClickedDecrement" -> UserClickedDecrement
        _ -> crash("Unsupported event type \"${raw}\"")
```

[See more examples](https://github.com/niclas-ahden/joy/tree/main/examples)

## Try it out

Clone the repo and use the included Nix flake to set up your development environment:

```sh
$ nix develop # Oh, lord, have mercy! This is great!
```

If you don't want to use Nix then please install:

* [`roc`](https://www.roc-lang.org/install) (see [Roc compiler and roc_std versions](#roc-compiler-and-roc_std-versions) below)
* `zig 13`
* `rustc`
* `cargo`
* `lld`
* [`wasm-pack`](https://rustwasm.github.io/wasm-pack/installer/)
* `simple-http-server`
* `inotify-tools` (on Linux)
* `watchexec`

### Run an example

Pick an [example](https://github.com/niclas-ahden/joy/tree/main/examples) and run it like so:

```sh
$ ./watch.sh examples/hello.roc
```

The application should now be available at: [`http://localhost:3000`](http://localhost:3000)

Start modifying the example to get a feel for it. Refresh the browser to see your changes (the app is recompiled on change but there's no browser hot-reloading yet).

### Deploying an app

#### Full-stack apps

TBD

#### SPA / Client-side apps

Delete existing assets then build for release:

```sh
$ rm -rf ./www/pkg
$ ./build.sh --release examples/hello.roc
```

You'll end up with a complete front-end app in the `www` directory. You can deploy that anywhere as you see fit.

## Contributing

Contributions are very welcome, including feature requests, design discussion, etc.

## Development setup

Do everything under "Try it out" and you're golden.

The `./watch.sh` script will recompile your Roc application and the client-side platform on change.

### CLI

Using WASI to debug the Roc FFI without the complications of `wasm-pack` and the browser.

Install [`bytecodealliance/cargo-wasi`](https://github.com/bytecodealliance/cargo-wasi), then:

```sh
$ ./run-cli.sh examples/hello.roc
```

### Roc compiler and `roc_std` versions

The Joy client-side platform is written in Rust and depends on the crate `roc_std` from the Roc project. You must ensure that your Roc compiler version is the same as the `roc_std` version that Joy uses.

#### Using Nix flake (recommended)

This is taken care of for you if you use the Nix flake. We ensure that the Roc compiler version in `flake.lock` and the `roc_std` version in `Cargo.lock` are the same.

If you want to change which versions are used you can specify the version or commit in `flake.nix` and `Cargo.toml`.

You can also just update to the latest commit of both like so:

```sh
$ nix flake update roc
$ cargo update roc_std
```

#### Not using Nix flake

If you're not using the Nix flake you'll need to ensure that the versions line up yourself. It's probably easiest to install the version of Roc that you'd like and then specify that version of `roc_std` in `Cargo.toml`.

## Sponsors

Joy is sponsored by the real estate agency [BOSTHLM Fastighetsmäklare](https://www.bosthlm.se) which thrives by using technology to bolster its agents and business. Thank you!

Have a look at their search feature on [www.bosthlm.se/till-salu](https://www.bosthlm.se/till-salu) which is a front-end application written in Roc.
