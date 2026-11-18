# Joy TodoMVC

[TodoMVC](https://todomvc.com) written in [Joy](https://github.com/niclas-ahden/joy), a framework for building web apps in [Roc](https://www.roc-lang.org). It is a small but complete single-page app, with no server of its own: `./joy build` writes a folder any static host can serve. To start an app of your own, run `./joy init` in an empty folder instead of copying this one.

## Run it

The example is a Joy project inside the Joy repository, and its app builds against the checkout's platform. Use the repository's dev shell (`nix develop` at the root), and install `./joy`, the command line every Joy project has, in this folder:

```sh
$ roc build --opt=dev ../../cli/main.roc --output=joy
```

Then:

```sh
$ ./joy dev
```

Your app is now running at [`http://localhost:8000`](http://localhost:8000). Edit `client/app.roc` and save: the open page takes the new build and keeps the todos you typed. `./joy dev --port 8080` serves on another port.

For deploying, `./joy build` writes `dist/client/`: the page, the stylesheet and the app's wasm under names with a hash of their content, and Joy's runtime with only the browser features the app calls.

## Test it

```sh
$ roc tests.roc
```

Builds what ships with `./joy build` into `.joy/test/build/` and drives it through a real Chromium, so this one also wants [`playwright`](https://playwright.dev) with a chromium installed, and [`caddy`](https://caddyserver.com) to serve the build (`nix develop` covers both). Every `e2e/*_test.roc` is a standalone Roc program that steers the browser with [roc-playwright](https://github.com/niclas-ahden/roc-playwright), and [roc-spec](https://github.com/niclas-ahden/roc-spec) runs them in parallel, each worker against its own server. `roc tests.roc edit` runs only the tests whose name contains "edit", and `--fail-fast` stops at the first failure.

A full run ends with a smoke pass over the loop you work in: it starts `./joy dev` and runs a browser test against it.

## Structure

* `client/app.roc` is the app: model, messages, update and view. This is the file to play with. A Joy app in `client/` is a bundle, and `./joy` builds every one it finds there.
* `public/index.html` is the page. The element with `data-joy-bundle="app"` is where the app mounts, and `joy.js` is Joy's loader.
* `assets/css/style.css` is the stylesheet. A build gives a file in `assets/` a hashed name and puts that name in the page.
* `tests.roc` and `e2e/` drive the app through a real Chromium, then smoke test `./joy dev`.

## Learn more

* [Joy's documentation](https://niclas-ahden.github.io/joy) for the platform API.
* [More Joy examples](https://github.com/niclas-ahden/joy/tree/main/examples), most of them a single file.
* [A tour of Roc's syntax](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md) if the language is new to you.
