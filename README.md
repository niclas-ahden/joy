# Joy

A framework for building full-stack web apps in Roc!

Joy is a jolt of happiness for those who want a fast, productive, fun, and statically-typed environment for full-stack development.

## Goals

Joy should provide:
* A convenient way of writing full-stack apps all in Roc (sometimes called "isomorphic" apps).
* A convenient way of communicating between the front- and back-end (think [Server Functions](https://book.leptos.dev/server/25_server_functions.html) or a protocol for message-passing over Server-Sent Events, websockets, and/or plain old requests).
* Great developer experience (feedback, iteration time, tooling, etc.)
* Great performance for the vast majority of apps, but not at any cost.

## Status

Joy is fun to play with, but it's in early development, not production-ready. Here be dragons!

You can already build single-page applications in it but the functionality is limited. Have a look at the [examples](https://github.com/niclas-ahden/joy/tree/main/examples) to get a grasp on what's currently supported. See [Joy TodoMVC](https://www.github.com/niclas-ahden/joy-todomvc) for a complete front-end example.

A full-stack example will follow! In the meantime you can use [`roc-lang/basic-webserver`](https://www.github.com/roc-lang/basic-webserver) and [`joy-html`](https://www.github.com/niclas-ahden/joy-html) to serve Joy HTML from the back-end.

Have fun and expect breaking changes!

## Example

A client-side counter:

```roc
app [Model, Msg, init, update, render, subscriptions] {
    pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.32.1/BBEFdA1VAk1WZvQWKs3yNfN2RMdZZP5DsM8j7gyNoFta.tar.zst",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]

Model : { count : I64 }

Msg : [Increment, Decrement]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
    match msg {
        Increment => ({ count: model.count + 1 }, [])
        Decrement => ({ count: model.count - 1 }, [])
    }

render : Model -> Html(Msg)
render = |model|
    div(
        [],
        [
            button([on_click(Increment)], [text("+")]),
            text(model.count.to_str()),
            button([on_click(Decrement)], [text("-")]),
        ],
    )
```

[See more examples](https://github.com/niclas-ahden/joy/tree/main/examples) | [TodoMVC](https://www.github.com/niclas-ahden/joy-todomvc)

## Getting started

Start with the [Joy TodoMVC](https://www.github.com/niclas-ahden/joy-todomvc) example, and you'll have a complete front-end app setup in no time!

## Performance

Joy is tracked against the [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark), with one keyed and one non-keyed entry. Numbers below are from a local run and gives you a rough idea of our relative performance:

| | Joy (keyed) | Joy (non-keyed) | Elm (keyed) | Elm (non-keyed) | React | vanilla JS |
|---|---|---|---|---|---|---|
| CPU geomean (ms) | 40.7 | 36.4 | 32.5 | 30.4 | 41.9 | 23.9 |
| Slowdown vs best | 1.83× | 1.64× | 1.46× | 1.37× | 1.88× | 1.07× |
| Memory (MB) | 7.7 | 7.7 | 1.3 | 1.3 | 2.2 | 0.8 |
| Bundle, compressed (KB) | 45.3 | 45.3 | 7.9 | 8.2 | 51.4 | 2.4 |

## Contributing

Contributions are very welcome, including feature requests, design discussion, etc.

## Development setup

### Dependencies

Clone the repo and use the included Nix flake to set up your development environment:

```sh
$ nix develop # Oh, lord, have mercy! This is great!
```

If you don't want to use Nix then please install:

* [`roc nightly-2026-08-16-23452ea`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-08-16-23452ea)
* `rustc` (v1.94 + `wasm32-unknown-unknown`)
* `node` (v22)
* `watchexec`

### Running an example

Pick an [example](https://github.com/niclas-ahden/joy/tree/main/examples) and run it like so:

```sh
$ ./watch.roc examples/hello.roc
```

The application should now be available at: [`http://localhost:8000`](http://localhost:8000)

Start modifying the example to get a feel for it. Refresh the browser to see your changes (the app is recompiled on change but there's no browser hot-reloading yet).

### Running the tests

```sh
$ ./tests.roc # Roc unit tests + the fake-DOM harnesses in tests/
$ ./e2e.roc   # tests/e2e/ in a real headless Chromium
```

The harnesses in `tests/` mount the built apps on a fake DOM and cover the app and runtime logic. The browser suite in `tests/e2e/` is built on [roc-spec](https://github.com/niclas-ahden/roc-spec) and [roc-playwright](https://github.com/niclas-ahden/roc-playwright) and covers what only a real browser can prove: real event dispatch and bubbling, `<dialog>` semantics, the History API, WebCrypto, fetch, real timers, and real keyboard and mouse input. CI runs both.

## Sponsors

Joy is sponsored by the real estate agency [BOSTHLM Fastighetsmäklare](https://www.bosthlm.se) which thrives by using technology to bolster its agents and business. Thank you!

Have a look at their search feature on [www.bosthlm.se/till-salu](https://www.bosthlm.se/till-salu) which is a front-end application written in Roc.
