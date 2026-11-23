# A Joy app

This project started from Joy's **spa-minimal** template, the smallest Joy
app there is. It's one file with a counter in it, the same one the guide
walks you through in [Your first app](https://niclas-ahden.github.io/joy/#first-app).

Pick it when you want to learn Joy, try out an idea, or build something
that fits on a single screen, like a calculator, a game or a widget for a
page you already have. When you want more pages with a URL each, start from
`spa-pages` instead.

    ./joy dev        work on it at http://localhost:8000
    ./joy build      build what ships into dist/client/, for any static host
    ./joy upgrade    move the project to a newer Joy release

With `./joy dev` running, change some text in `client/app.roc` and save.
The page updates right away :)

## What's in it

- `client/app.roc` is your app: its model, its messages, and the `init`,
  `update`, `view` and `subscriptions` functions.
- `public/index.html` is the HTML page that loads your app. Your own
  `<head>` tags go here.
- `assets/` is for the stylesheets, images and fonts your page links to.
  `./joy build` puts a hash in each file name, so browsers can cache them
  and still get the new version after a deploy.

The [Joy guide](https://niclas-ahden.github.io/joy/) takes it from here:
views, HTTP requests, timers, and talking to JavaScript.

## On another machine

`./joy` is built for the machine it runs on, so it isn't committed to git.
When you or a teammate clone your project somewhere else, install `./joy`
there with:

    <INSERT JOY INSTALL COMMAND HERE>

It leaves your app as it is.
