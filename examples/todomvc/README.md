# Joy TodoMVC

[TodoMVC](https://todomvc.com) written in [Joy](https://github.com/niclas-ahden/joy), a framework for building web apps in [Roc](https://www.roc-lang.org). It is a small but complete app, so it is also the fastest way to start one of your own: clone it and edit `app.roc`.

## Run it

You need [`caddy`](https://caddyserver.com/docs/install) and Roc on your PATH (we recommend [`roc nightly-2026-08-29-2d69988`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-08-29-2d69988)). Download the archive for your platform from that page, extract it, and put the `roc` binary on your PATH. If you use Nix, `nix develop` hands you both instead.

Then:

```sh
$ git clone https://github.com/niclas-ahden/joy-todomvc
$ cd joy-todomvc
$ ./watch.roc
```

Your app is now running at [`http://localhost:8000`](http://localhost:8000). Edit `app.roc` and it recompiles on save. Refresh the browser to see your changes (there is no hot-reloading yet). Set `JOY_WATCH_PORT` to serve on another port.

That is the whole setup. `app.roc`'s header names Joy and [`joy-html`](https://github.com/niclas-ahden/joy-html) by URL, so Roc downloads them for you on the first build and there is nothing else to install or compile.

Roc is a moving target, so which version you use matters. We test the latest Joy release against the newest nightly every morning and move the name above forward whenever it passes. Each [Joy release](https://github.com/niclas-ahden/joy/releases) also names the nightly it shipped against, under "Roc compiler version". The `nix develop` shell pins its own compiler and may build it from source the first time, which takes a while. After that it comes from the Nix cache.

## Test it

```sh
$ ./tests.roc
```

Builds the app and drives it through a real Chromium, so this one also wants [`playwright`](https://playwright.dev) with a chromium installed (`nix develop` covers it). Every `tests/*_test.roc` is a standalone Roc program that steers the browser with [roc-playwright](https://github.com/niclas-ahden/roc-playwright), and [roc-spec](https://github.com/niclas-ahden/roc-spec) runs them in parallel, each worker against its own server. `./tests.roc edit` runs only the tests whose name contains "edit", and `--fail-fast` stops at the first failure.

A full run ends with a smoke pass over the dev loop itself: it starts `./watch.roc` and runs a browser test against it, so the scripts you develop with are tested too.

## Structure

The whole app is this directory:

* `app.roc` is the app: model, messages, update, and render. This is the file to play with.
* `www/` is its page and styles. `build.roc` puts the compiled `app.wasm` and Joy's `runtime.js` next to them (both gitignored).
* `watch.roc` serves the app and rebuilds it on save.
* `tests.roc` and `tests/` drive the app through a real Chromium, then smoke test `watch.roc`.
* `Caddyfile` is the static file server `watch.roc` and the test servers share.

## Learn more

* [Joy's documentation](https://niclas-ahden.github.io/joy) for the platform API.
* [More Joy examples](https://github.com/niclas-ahden/joy/tree/main/examples), each a single file.
* [A tour of Roc's syntax](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md) if the language is new to you.

Play around with it, it's a great starting point for a web app!
