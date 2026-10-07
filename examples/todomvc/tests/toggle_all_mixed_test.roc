app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# Toggle-all from a mixed state completes every todo, it does not invert
# each one
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "One")?
	TodoPage.add!(page, "Two")?
	TodoPage.add!(page, "Three")?
	page.find(TodoPage.toggle(2)).check!()?

	page.find(".toggle-all").check!()?
	assert!(page.find_all(".todo-list li.completed").has_count(3)) ? |e| AllShouldBeCompleted(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("0 items left")) ? |e| NothingShouldBeLeft(Str.inspect(e))

	browser.close!()
}
