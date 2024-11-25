app [main!] { web: platform "../platform/main.roc" }

import web.Console
import web.Dom

main! : {} => Result {} _
main! = \{} ->

    bodyHtml = try Dom.getInnerHtml! "thing"

    Console.log! "GOT THING HTML\n$(bodyHtml)"

    Ok {}
