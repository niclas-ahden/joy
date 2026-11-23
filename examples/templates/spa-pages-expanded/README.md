# A Joy app

This project started from Joy's **spa-pages-expanded** template. Like
`spa-pages`, it's a single-page app with proper navigation. The difference
is how the code is organized: here each page is like a little app of its
own, with its own model, messages and `update`.

Pick it for a bigger app, where pages have forms, searches and other state
that only matters on that page. A page keeps that state to itself, and it's
cleared when you leave, so you start fresh the next time you visit. Data
the whole app needs, like the signed-in user or a shopping cart, goes in
the app's model, and the pages that need it get it from there.

The example is a small notebook. The Notes page lists your notes, adds and
removes them, and searches them as you type. Each note has a page of its
own at `/notes/<id>`. Quote fetches a quote from an API, and About is plain
text. The notes belong to the app, so they stay when you switch pages,
while the search on the Notes page is cleared.

    ./joy dev        work on it at http://localhost:8000
    ./joy build      build what ships into dist/client/, for any static host
    ./joy upgrade    move the project to a newer Joy release

## What's in it

- `client/app.roc` is your app: the notebook, the page you're on, the menu,
  and what happens when the URL changes. It never mentions a single page.
- `client/Page.roc` knows every page. It has the same `init`, `update`,
  `view` and `subscriptions` an app has, and each one passes the call on to
  the page you're on.
- `client/Page/` has a module per page, each with its own model and
  messages.
- `client/Notebook.roc` has the notes, and how to add, remove and search
  them.
- `client/Route.roc` has every URL of the app. Make your links with
  `Route.to_path`, so a URL is only ever written in this file.
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
2. Add its module to `client/Page/`, with `init`, `update` and `view`.
3. In `client/Page.roc`, add a tag for it to `Page` and to `Msg`, and a line
   for it in `route`, `init`, `update`, `view` and `subscriptions`.

Once the tags are there the compiler points out most of what's missing :)

## Deploying

A static host has to answer with `index.html` for every URL of your app, or
a refresh on `/quote` gives you a 404. On Netlify that's the line
`/* /index.html 200` in `public/_redirects`.

## On another machine

`./joy` is built for the machine it runs on, so it isn't committed to git.
When you or a teammate clone your project somewhere else, install `./joy`
there with:

    <INSERT JOY INSTALL COMMAND HERE>

It leaves your app as it is.
