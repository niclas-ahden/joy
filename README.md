# Joy

A framework for building full-stack web apps in Roc!

Joy is a jolt of happiness for those who want a fast, productive, fun, and statically-typed environment for full-stack development.

Try it out in your browser: [Joy guide](https://niclas-ahden.github.io/joy/) :)

## Goals

Joy should provide:
* A convenient way of writing full-stack apps all in Roc (sometimes called "isomorphic" apps).
* A convenient way of communicating between the front- and back-end (think [Server Functions](https://book.leptos.dev/server/25_server_functions.html) or a protocol for message-passing over Server-Sent Events, websockets, and/or plain old requests).
* Great developer experience (feedback, iteration time, tooling, etc.)
* Great performance for the vast majority of apps, but not at any cost.

## Status

Joy is fun to play with, but it's in early development, not production-ready. Here be dragons!

Try it out through the [Joy guide](https://niclas-ahden.github.io/joy/), it has interactive demos to get you going!

You can already build full-stack apps in Joy, but we don't have guides and examples for you yet. That'll come in Joy 0.36.0. If you're at the edge of your seat for full-stack apps, ping me on [the Roc Zulip](https://roc.zulipchat.com/) and I'll help you out :)

Have fun and expect breaking changes!

## Example

A client-side counter:

```roc
app [Model, Msg, init, update, view, subscriptions] {
    pf: platform "https://github.com/growthagent/joy/releases/download/0.35.0-rc6/C5LQnNqF9EBuhTKKHTyUTPAUH5wv9Wd82otSSSaVcJb3.tar.zst",
    html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [div, button, text]
import html.Attribute exposing [on_click]
import pf.Effect

Model : { count : I64 }

Msg : [Increment, Decrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
    match msg {
        Increment => ({ count: model.count + 1 }, [])
        Decrement => ({ count: model.count - 1 }, [])
    }

view : Model -> Html(Msg)
view = |model|
    div(
        [],
        [
            button([on_click(Increment)], [text("+")]),
            text(model.count.to_str()),
            button([on_click(Decrement)], [text("-")]),
        ],
    )

subscriptions = |_model| []
```

[Run it in your browser](https://niclas-ahden.github.io/joy/#example-counter) | [See more examples](https://github.com/niclas-ahden/joy/tree/main/examples) | [TodoMVC](https://github.com/niclas-ahden/joy/tree/main/examples/spa-todomvc)

## Getting started

[The Joy guide](https://niclas-ahden.github.io/joy/) gets you going step by step, and everything in it runs right in your browser.

* New to Joy? [Start from the beginning](https://niclas-ahden.github.io/joy/#welcome).
* Already know Joy? [Go straight to installation](https://niclas-ahden.github.io/joy/#install).

## Performance

Joy is tracked against the [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark), with keyed and non-keyed entries. Numbers below are from a local run and give you a rough idea of our relative performance:

| | Joy (keyed) | Joy (non-keyed) | Elm (keyed) | Elm (non-keyed) | Leptos | SolidJS | React | vanilla JS |
|---|---|---|---|---|---|---|---|---|
| CPU geomean (ms) | 29.6 | 26.7 | 31.7 | 29.0 | 29.0 | 26.0 | 40.7 | 22.4 |
| Slowdown vs best | 1.42× | 1.28× | 1.52× | 1.39× | 1.39× | 1.24× | 1.95× | 1.07× |
| Memory (MB) | 3.6 | 3.6 | 1.3 | 1.3 | 3.5 | 1.0 | 2.2 | 0.8 |
| Bundle, compressed (KB) | 27.5 | 27.3 | 7.9 | 8.2 | 48.8 | 4.5 | 51.4 | 2.4 |

Bundle is the brotli-compressed transfer of everything the page loads, so for Joy that covers the WASM, the JS runtime, and the HTML. The WASM is the bulk of it at 22.1 KB, and the minified JS runtime is 5.0 KB.

Every framework in the table was measured in one session on a machine running NixOS, x86, AMD 9950X. Hopefully we can get Joy into the official benchmark soon!

## Known issues

- On a server-rendered page, hydration may remove or adopt a node that an extension or another script adds before `mount` is called.
- An extension that replaces the app's text with its own nodes, the way a page translator does, hides later changes to that text.

## Contributing

Contributions are very welcome, including feature requests, design discussion, etc.

## Development setup

### Dependencies

Clone the repo and use the included Nix flake to set up your development environment:

```sh
$ nix develop # Oh, lord, have mercy! This is great!
```

If you don't want to use Nix then please install:

* `roc` built from source at the commit `flake.nix` pins in `roc-src.url`.
* `rustc` (v1.94 + `wasm32-unknown-unknown`)
* `node` (v22)
* `watchexec`
* `playwright` with its browsers, for the browser E2E suite (`npm install -g playwright && playwright install chromium firefox webkit`)

The scripts in the repo root are Roc programs: on Linux and macOS their shebang runs them (`./tests.roc --opt=speed`), on Windows hand them to roc (`roc ./tests.roc --opt=speed`), which works everywhere.

### Starting a project from your clone

To start a project that builds against your clone instead of a release, run the command line from the clone and name the clone:

```sh
$ roc run ~/src/joy/cli/main.roc init --joy-checkout ~/src/joy
```

### Running an example

To serve an [example](https://github.com/niclas-ahden/joy/tree/main/examples) from your clone while you work on Joy:

```sh
$ ./watch.roc examples/hello.roc
```

The application should now be available at: [`http://localhost:8000`](http://localhost:8000)

That builds at `--opt=speed`, the default. To pick another level, pass it after the script: `./watch.roc --opt=dev examples/hello.roc`.

The app is recompiled when you save. Refresh the browser to see the change.

### Running the tests

```sh
$ ./tests.roc                # Roc unit tests and the fake-DOM harnesses in tests/
$ ./e2e.roc                  # the browser suite in tests/e2e/, in headless Chromium
$ ./e2e.roc --browser=all    # the same in Chromium, Firefox and WebKit
$ roc cli/tests.roc          # the tests of the ./joy command line
$ ./examples.roc             # the suite of each example that has one (examples/*/tests.roc)
```

`./tests.roc` and `./e2e.roc` build at `--opt=dev`, the quickest while you work. Add `--opt=speed` to test the builds an app ships with. CI runs every level, and each one builds into its own `build/<opt>/`.

**The fake-DOM harnesses** in `tests/` mount the built apps on a fake DOM and cover the app and runtime logic.

* They find elements the way the browser suite does: by role and accessible name, label or test id (`byRole`, `byLabel` and `byTestId` in `tests/fakedom.mjs`).
* They can put a work budget on a step. `meter` in `tests/harness.mjs` counts patch ops and DOM mutations, so a test can check that a click cost one text write and no rebuild.

**The browser suite** in `tests/e2e/` runs on [roc-spec](https://github.com/niclas-ahden/roc-spec) and [roc-playwright](https://github.com/niclas-ahden/roc-playwright). It covers the parts which actually need a real browser, such as event dispatch and bubbling, `<dialog>`, the History API, WebCrypto, fetch, real timers, keyboard and mouse input, and recording from a fake microphone.
