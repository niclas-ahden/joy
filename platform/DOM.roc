module [
    close_modal!,
    show_modal!,
]

import Host

## Call `showModal()` on the `<dialog>` matching the given CSS selector.
show_modal! : Str => {}
show_modal! = |selector| Host.dom_show_modal!(selector)

## Call `close()` on the `<dialog>` matching the given CSS selector.
close_modal! : Str => {}
close_modal! = |selector| Host.dom_close_modal!(selector)
