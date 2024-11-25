app [main!] { web: platform "../platform/main.roc" }

import web.Console

main! : {} => Str
main! = \{} ->

    Console.log! "Logging from Roc"

    "Hello from Roc"
