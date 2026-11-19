# A Joy app

A small app on [Joy](https://github.com/niclas-ahden/joy) in one file: a
count and two buttons.

    ./joy dev      work on it at http://localhost:8000
    ./joy build    build what ships into dist/client/, for any static host

- `client/app.roc` is the app.
- `public/index.html` is the page that loads the app.
- `assets/` has the files your page links to. A build gives each a hashed
  name.

## After a clone

`./joy` is built for each machine, so it stays out of git. In a fresh
clone, install it with:

    JOY_INSTALL_COMMAND

It installs `./joy` and leaves the app as it is.
