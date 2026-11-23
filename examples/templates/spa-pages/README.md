# A Joy app

This project started from Joy's **spa-pages** template: a single-page app
with a few pages and proper navigation.

Pick it for an app with a handful of pages, like a portfolio, a dashboard
or a small admin tool. The whole app has one model that every page reads
from, so data one page changes is right there on the others. If your
pages grow big, with forms and searches of their own, have a look at
`spa-pages-expanded`.

It comes with three pages to replace with your own. Home has a counter
that keeps its count while you visit the other pages, Quote fetches a
quote from an API, and About is plain text.

    ./joy dev        work on it at http://localhost:8000
    ./joy build      build what ships into dist/client/, for any static host
    ./joy upgrade    move the project to a newer Joy release

## What's in it

- `client/app.roc` is your app: the model, the messages, the menu, and
  which page to show for a URL.
- `client/Route.roc` has every URL of the app. Make your links with
  `Route.to_path`, so a URL is only ever written in this file.
- `client/Page/` has a module per page. A page here is just a view. The
  app hands it what to show and which messages to send.
- `public/index.html` is the HTML page that loads your app.
- `assets/` is for the stylesheets, images and fonts your pages link to.
  `./joy build` puts a hash in each file name, so browsers can cache them
  and still get the new version after a deploy.

Quote talks to the [Ron Swanson Quotes API](https://github.com/jamesseanwright/ron-swanson-quotes),
which is someone else's server. This app doesn't have one of its own.

## Adding a page

1. Add a tag for it to `Route` in `client/Route.roc`, and a line for it in
   `parse`, `to_path` and `label`. Put it in `menu` too if it belongs in
   the menu.
2. Add its module to `client/Page/`, with a `view`.
3. Show it in `view_page` in `client/app.roc`. If it needs data of its own,
   add that to `Model`, and its messages to `Msg`.

Once the tag is there the compiler points out most of what's missing :)

## Deploying

A static host has to answer with `index.html` for every URL of your app, or
a refresh on `/about` gives you a 404. On Netlify that's the line
`/* /index.html 200` in `public/_redirects`.

## On another machine

`./joy` is built for the machine it runs on, so it isn't committed to git.
When you or a teammate clone your project somewhere else, install `./joy`
there with:

    <INSERT JOY INSTALL COMMAND HERE>

It leaves your app as it is.
