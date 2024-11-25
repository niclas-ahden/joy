app [main!] { web: platform "../platform/main.roc" }

import web.Console

main! : {} => Result {} []
main! = \{} ->

    Console.log! "Logging from Roc"

    Ok {}
