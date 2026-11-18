# A Joy app

A single-page app on [Joy](https://github.com/niclas-ahden/joy): several
pages, with a URL for each and Back and Forward working.

    ./joy dev      work on it at http://localhost:8000
    ./joy build    build what ships into dist/client/, for any static host

- `client/app.roc` is the app: the model, the messages, the menu and
  which page is on screen.
- `client/Route.roc` has every URL of the app.
- `client/Page/` has a module per page. A page is a view of the model. The
  Quote page shows a quote from the Ron Swanson Quotes API, which is
  someone else's server. This app has no server of its own.
- `public/index.html` is the page that loads the app.
- `assets/` has the files the pages link to. A build gives each a hashed
  name.

A static host has to answer `index.html` for the app's own paths, so a
refresh on `/about` opens the app. On Netlify that is `/* /index.html 200`
in `public/_redirects`.

## After a clone

`./joy` is built for each machine, so it stays out of git. In a fresh
clone, install it with:

    JOY_INSTALL_COMMAND

It installs `./joy` and leaves the app as it is.
