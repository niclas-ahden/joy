module [
    close_modal!,
    show_modal!,
]

import Host

show_modal! : Str => {}
show_modal! = |selector| Host.show_modal!(selector)

close_modal! : Str => {}
close_modal! = |selector| Host.close_modal!(selector)
