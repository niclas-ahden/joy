# Joy TodoMVC

[TodoMVC](https://todomvc.com) written in [Joy](https://github.com/niclas-ahden/joy), a framework for building web apps in [Roc](https://www.roc-lang.org). The whole app is this directory:

* `app.roc` is the app: model, messages, update, and render.
* `www/` is its page and styles. `build.roc` puts the compiled `app.wasm` and Joy's `runtime.js` next to them.
* `watch.roc` serves the app and rebuilds it on save.
* `tests.roc` and `tests/` drive the app through a real Chromium, then smoke test `watch.roc`.
* `Caddyfile` is the static file server `watch.roc` and the test servers share.

`app.roc`'s header names the Joy platform. In a clone of joy-todomvc that is a released Joy bundle, so there is nothing to build but the app itself. Inside the Joy repo it is the checkout's platform by path, so the checkout's wasm host must exist (run `./build.roc` at the repo root once). There, Joy's own tooling runs this app too: `./watch.roc examples/todomvc` from the repo root, and `./e2e.roc` picks up `tests/` along with the rest of the browser suite.

## Run it

```sh
$ nix develop
$ ./watch.roc
```

The app is now available at [`http://localhost:8000`](http://localhost:8000). Edit `app.roc` and it recompiles on save. Refresh the browser to see your changes (there is no hot-reloading yet). Set `JOY_WATCH_PORT` to serve on another port.

If you don't want to use Nix then please install:

* [`roc`](https://github.com/roc-lang/nightlies/releases) (a recent nightly)
* [`caddy`](https://caddyserver.com/docs/install)
* [`playwright`](https://playwright.dev) with a chromium (only needed for ./tests.roc)

## Test it

```sh
$ nix develop
$ ./tests.roc
```

Builds the app and drives it through a real Chromium. Every `tests/*_test.roc` is a standalone Roc program that steers the browser with [roc-playwright](https://github.com/niclas-ahden/roc-playwright), and [roc-spec](https://github.com/niclas-ahden/roc-spec) runs them in parallel, each worker against its own server. `./tests.roc edit` runs only the tests whose name contains "edit", and `--fail-fast` stops at the first failure.

A full run ends with a smoke pass over the dev loop itself: it starts `./watch.roc` and runs a browser test against it, so the scripts you develop with are tested too.
