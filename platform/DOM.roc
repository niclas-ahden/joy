module [
    close_modal!,
    show_modal!,
    navigate!,
    replace_url!,
    push_url!,
]

import Host

## Call `showModal()` on the `<dialog>` matching the given CSS selector.
show_modal! : Str => {}
show_modal! = |selector| Host.dom_show_modal!(selector)

## Call `close()` on the `<dialog>` matching the given CSS selector.
close_modal! : Str => {}
close_modal! = |selector| Host.dom_close_modal!(selector)

## Navigate the browser to `url` by setting `window.location.href`. This always
## triggers a full page load, even when `url` matches the current one, and it
## pushes a history entry so Back and Forward work. Use it to move between
## server-rendered pages.
navigate! : Str => {}
navigate! = |url| Host.dom_navigate!(url)

## Change the URL without loading a new page, replacing the current history
## entry in place (`history.replaceState`). It does not grow the history stack.
## This is what you want for reflecting in-page state in the URL, such as a
## search box where `?q=hats` should track what the user typed without recording
## a separate history entry per keystroke (otherwise Back would step through
## every character). No router needed, because the view already reflects your
## `Model` and you are only updating the address bar to match it.
##
## NOTE: browsers may rate-limit this. Safari has been seen to throw after about
## 100 calls in 30 seconds, so update on a debounced value, not every keystroke.
replace_url! : Str => {}
replace_url! = |url| Host.dom_replace_url!(url)

## Push a new URL onto the history stack (`history.pushState`). No reload, but
## adds a history entry so Back returns to the previous URL.
##
## NOTE: Joy has no client-side router yet. Pushing a URL does NOT re-render
## the page, and a later Back or Forward fires `popstate`, which Joy ignores, so
## the URL and the view can desync. Only use this if you handle that yourself.
## To keep the URL in sync with state (search boxes, filters) prefer
## [replace_url!]. To move between pages prefer [navigate!].
push_url! : Str => {}
push_url! = |url| Host.dom_push_url!(url)
