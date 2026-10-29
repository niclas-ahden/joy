# A Joy app

A single-page app on [Joy](https://github.com/niclas-ahden/joy): pages in one
bundle, with a URL for each and Back and Forward working.

    ./joy dev      work on it at http://localhost:8000
    ./joy build    build what ships into dist/client/, for any static host

- `client/app.roc` is the bundle: which page is on screen and the links.
- `client/Route.roc` has every URL of the app.
- `client/Page/` has a module per page.
- `public/index.html` is the page that loads the app.
- `assets/` has the files your pages link to. A build gives each a hashed
  name.

A static host has to answer `index.html` for the app's own paths, so a
refresh on `/about` opens the app. On Netlify that is `/* /index.html 200`
in `public/_redirects`.

## After a clone

`./joy` is built for each machine, so it stays out of git. In a fresh
clone, install it with:

    JOY_INSTALL_COMMAND

It installs `./joy` and leaves the app as it is.
