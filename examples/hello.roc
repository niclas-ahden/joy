app [main!] { dom: platform "../platform/main.roc" }

main! : {} => Str
main! = \{} ->
    "Hello from Roc"
