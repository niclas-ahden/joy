app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "First")?
	TodoPage.add!(page, "Second")?
	TodoPage.add!(page, "Third")?

	# The button only exists while something is completed
	assert!(page.find(".clear-completed").is_hidden()) ? |e| NothingToClearNoButton(Str.inspect(e))

	page.find(TodoPage.toggle(1)).check!()?
	page.find(TodoPage.toggle(3)).check!()?
	assert!(page.find(".clear-completed").is_visible()) ? |e| ButtonShouldAppear(Str.inspect(e))

	page.find(".clear-completed").click!()?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| CompletedShouldBeGone(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Second")) ? |e| TheActiveTodoShouldSurvive(Str.inspect(e))
	assert!(page.find(".clear-completed").is_hidden()) ? |e| ButtonShouldGoAway(Str.inspect(e))

	browser.close!()
}
