app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# The list section and footer only exist while there are todos,
# per the TodoMVC spec
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	assert!(page.find(".main").is_hidden()) ? |e| NoListSectionBeforeTodos(Str.inspect(e))
	assert!(page.find(".footer").is_hidden()) ? |e| NoFooterBeforeTodos(Str.inspect(e))

	# Enter on the empty input changes nothing
	page.key_press!(".new-todo", Enter, [])?
	assert!(page.find(".main").is_hidden()) ? |e| EmptySubmitShouldChangeNothing(Str.inspect(e))

	TodoPage.add!(page, "Only todo")?
	assert!(page.find(".main").is_visible()) ? |e| ListSectionShouldAppear(Str.inspect(e))
	assert!(page.find(".footer").is_visible()) ? |e| FooterShouldAppear(Str.inspect(e))

	TodoPage.destroy!(page, 1)?
	assert!(page.find(".main").is_hidden()) ? |e| ListSectionShouldGoAway(Str.inspect(e))
	assert!(page.find(".footer").is_hidden()) ? |e| FooterShouldGoAway(Str.inspect(e))

	browser.close!()
}
