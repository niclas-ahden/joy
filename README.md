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

You can already build single-page applications in it but the functionality is limited. Have a look at the [examples](https://github.com/niclas-ahden/joy/tree/main/examples) to get a grasp on what's currently supported. See [Joy TodoMVC](https://github.com/niclas-ahden/joy/tree/main/examples/spa-todomvc) for a complete front-end example.

As an app grows, split it into pages: each page is a module with its own `Model`, `Msg`, `init`, `update` and `view`, and the app wraps them with `Html.map`, `Effect.map` and `Sub.map`. The [pages example](https://github.com/niclas-ahden/joy/tree/main/examples/pages) gives every page its own URL and holds only the page on screen, the shape of a server-rendered app, and the [spa_pages example](https://github.com/niclas-ahden/joy/tree/main/examples/spa_pages) switches pages in place and keeps every page's state.

Joy also does hydration: serve a page rendered with [`joy-html`](https://www.github.com/niclas-ahden/joy-html) and mount with `hydrate: true`, and the client's first render claims the server-rendered DOM (attaching event handlers) instead of rebuilding it.

Joy shares the page with whatever else is on it. Browser extensions and embedded widgets put nodes of their own among the app's (a speed control next to a video, a password manager's icon next to a field, a map drawn into an empty container), and Joy leaves them alone: it keeps track of its own nodes itself and never goes by their position in the DOM. That holds while a server-rendered page waits for its app to load, too, with one difference: nodes an extension puts in place of the page's own in that time (a translation for a text, a wrapper around a video) give way to the app's nodes when it starts, so the page never shows both.

Joy reaches into the browser where an app needs it. `Media` records from the microphone or camera, reports loudness while recording, hands the recording over as an ordinary file (the same kind a file input gives, so it uploads and hashes like one) and plays audio and video: see the [voice memo example](https://github.com/niclas-ahden/joy/tree/main/examples/voice_memo.roc). A capture is a subscription, so the microphone is open exactly while the app subscribes to it and closes on its own when it stops.

A released app's `runtime.js` carries the browser code of exactly the platform functions it calls. Everything past rendering is a browser feature: HTTP, timers, the keyboard, ports, navigation and dialogs, Web Crypto and media. The compiler drops the functions an app never calls, and the build reads which feature operations are left in the app's wasm and adds just their code to Joy's core (see `tools/runtime`), so an app that only plays audio ships no recording code and one that uses no browser features ships the core alone. During development `runtime.js` holds every feature instead, because the wasm changes on nearly every edit and a pruned runtime would have to be rebuilt in step with it. A browser feature is a platform module built on `Effect.call`, `Effect.send` and `Sub.listen`, whose arguments and answers are a few bytes in a fixed order (see `Wire`), plus its JavaScript in `www/features/`, with no change to the host: see Features in `www/runtime.js`.

Have fun and expect breaking changes!

### Known issues

- Known issue: on a server-rendered page, a node an extension or another script adds before Joy's script has called `mount` cannot be told apart from the server's markup. Hydration removes it when it sits in front of a node the app expects (and warns about a mismatch), or takes it for the app's own when its tag matches. Nodes added from the `mount` call on are left alone.
- Known issue: an extension that replaces the app's text with nodes of its own, the way a page translator does, leaves Joy updating the original text nodes off the page, so later changes to that text do not show. Extensions that add nodes next to the app's are fine, and so are ones that wrap them once the app is running.

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

subscriptions = |_model| []

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
```

[See more examples](https://github.com/niclas-ahden/joy/tree/main/examples) | [TodoMVC](https://github.com/niclas-ahden/joy/tree/main/examples/spa-todomvc)

## Getting started

First install [Roc](https://www.roc-lang.org/). Joy follows Roc's nightly builds, and each release names the nightly it is tested with in its notes. The latest release is tested with [`roc nightly-2026-10-17-5f126ac`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-10-17-5f126ac). Another Roc can fail to build Joy's command line with an error that says nothing about versions.

Then make a folder for your project, and run Joy's command line in it:

```sh
mkdir my-app
cd my-app
roc run <cli url> init
```

Take `<cli url>` from the [latest release](https://github.com/niclas-ahden/joy/releases/latest). It takes a few seconds, most of them roc downloading the command line's packages. `init` asks what kind of app you want, writes it into the folder, and installs `./joy`, the command you use from then on:

```sh
./joy dev      # work on the app, and the page takes each change as you save
./joy build    # build what you deploy into dist/
```

Everything after the URL goes to the command line: `--template <name>` after `init` picks a template without asking, and `./joy init --help` lists them. `./joy` is built for your machine, so it stays out of git. After a fresh clone, the same command installs it and leaves the app as it is, and the project's README shows that command.

To build against a clone of this repository instead of a release, run the command line from the clone, with the Roc its [development setup](#dependencies) names, and name the clone:

```sh
roc run ~/src/joy/cli/main.roc init --joy-checkout ~/src/joy
```

For a complete front-end app to read, see [Joy TodoMVC](https://github.com/niclas-ahden/joy/tree/main/examples/spa-todomvc).

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

## Contributing

Contributions are very welcome, including feature requests, design discussion, etc.

## Development setup

### Dependencies

Clone the repo and use the included Nix flake to set up your development environment:

```sh
$ nix develop # Oh, lord, have mercy! This is great!
```

If you don't want to use Nix then please install:

* `roc` built from source at the commit `flake.nix` pins in `roc-src.url`. The nightly under [Getting started](#getting-started) is the one the latest release is tested with, and main can need a newer Roc than that.
* `rustc` (v1.94 + `wasm32-unknown-unknown`)
* `node` (v22)
* `watchexec`
* `playwright` with its browsers, for the browser E2E suite (`npm install -g playwright && playwright install chromium firefox webkit`)

That route is also the Windows one (Nix does not run there). The scripts in the repo root are Roc programs: on Linux and macOS their shebang runs them (`./tests.roc --opt=speed`), on Windows hand them to roc (`roc ./tests.roc --opt=speed`), which works everywhere.

### Running an example

Pick an [example](https://github.com/niclas-ahden/joy/tree/main/examples) and run it like so:

```sh
$ ./watch.roc examples/hello.roc
```

The application should now be available at: [`http://localhost:8000`](http://localhost:8000)

That builds at `--opt=speed`, the default. To pick another level, pass it after the script: `./watch.roc --opt=dev examples/hello.roc`.

Start modifying the example to get a feel for it. Refresh the browser to see your changes (the app is recompiled on change but there's no browser hot-reloading yet).

### Running the tests

```sh
$ ./tests.roc                # Roc unit tests + the fake-DOM harnesses in tests/
$ ./e2e.roc                  # tests/e2e/ in a real headless Chromium
$ ./e2e.roc --browser=all    # the same in Chromium, Firefox and WebKit
$ roc cli/tests.roc          # the tests of the ./joy command line
$ ./examples.roc             # each directory example's own suite (examples/*/tests.roc)
```

The harnesses in `tests/` mount the built apps on a fake DOM and cover the app and runtime logic. They find elements the way the browser suite does, by role and accessible name, label or test id (`byRole`, `byLabel`, `byTestId` in `tests/fakedom.mjs`), and they can put a work budget on a step: `meter` in `tests/harness.mjs` counts the patch ops the differ emitted and the DOM mutations made to apply them, so a harness asserts not only that the page looks right after a click but that the click cost one text write and no rebuild. The browser suite in `tests/e2e/` is built on [roc-spec](https://github.com/niclas-ahden/roc-spec) and [roc-playwright](https://github.com/niclas-ahden/roc-playwright) and covers what only a real browser can prove: real event dispatch and bubbling, `<dialog>` semantics, the History API, WebCrypto, fetch, real timers, real keyboard and mouse input, and recording from Chromium's fake microphone.

The first two build the apps at `--opt=dev`, which is the quick way round while you work. `./tests.roc --opt=speed` and `./e2e.roc --opt=speed` run the same suites against the builds an app ships with, and CI runs every level. Each level lands in its own `build/<opt>/` tree.

## Sponsors

Joy is sponsored by the real estate agency [BOSTHLM Fastighetsmäklare](https://www.bosthlm.se) which thrives by using technology to bolster its agents and business. Thank you!

Have a look at their search feature on [www.bosthlm.se/till-salu](https://www.bosthlm.se/till-salu) which is a front-end application written in Roc.
