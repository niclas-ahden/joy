# A Joy app

A single-page app on [Joy](https://github.com/niclas-ahden/joy) with
several pages, where a page has state and messages of its own, and the
notes are still there when you move between the pages.

    ./joy dev      work on it at http://localhost:8000
    ./joy build    build what ships into dist/client/, for any static host

- `client/app.roc` is the app: its model, its messages, the menu and what
  happens when the URL changes. It has no line about any one page.
- `client/Page.roc` is the page on screen: which pages there are, and the
  four parts of an app for whichever one is showing.
- `client/Notebook.roc` has the notes, and how to add, remove and search
  them.
- `client/Route.roc` has every URL of the app.
- `client/Page/` has a module per page. `About` is only a view. `Notes`
  shows and changes the notes, and its search waits for a pause in the
  typing. `Note` takes its note from the URL. `Quote` asks a server for its
  data: the Ron Swanson Quotes API, which is someone else's. This app has
  no server of its own.
- `public/index.html` is the page that loads the app.
- `assets/` has the files the pages link to. A build gives each a hashed
  name.

A static host has to answer `index.html` for the app's own paths, so a
refresh on `/quote` opens the app. On Netlify that is `/* /index.html 200`
in `public/_redirects`.

## Adding a page

1. A tag for its URL in `client/Route.roc`, with its lines in `parse`,
   `to_path` and `label`, and in `menu` if it belongs there.
2. Its module in `client/Page/`, with `init`, `update` and `view`.
3. In `client/Page.roc`: a tag in `Page`, a tag in `Msg`, and a line each in
   `route`, `init`, `update`, `view` and `subscriptions`.

Nothing changes in `client/app.roc`. The compiler asks for most of these
once the tags are there. It cannot see a missing line in `Route.parse`, or a
page left off the menu.

## After a clone

`./joy` is built for each machine, so it stays out of git. In a fresh
clone, install it with:

    JOY_INSTALL_COMMAND

It installs `./joy` and leaves the app as it is.
