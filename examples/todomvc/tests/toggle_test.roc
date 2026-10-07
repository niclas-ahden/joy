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

	page.find(TodoPage.toggle(1)).check!()?
	assert!(page.find_all(".todo-list li.completed").has_count(1)) ? |e| OneTodoShouldBeCompleted(Str.inspect(e))
	assert!(page.find("${TodoPage.row(1)}.completed").is_visible()) ? |e| TheToggledTodoShouldBeCompleted(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("1 item left")) ? |e| CompletedShouldLeaveTheCount(Str.inspect(e))

	# Toggling back revives the todo
	page.find(TodoPage.toggle(1)).uncheck!()?
	assert!(page.find_all(".todo-list li.completed").is_empty()) ? |e| NoTodoShouldBeCompleted(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("2 items left")) ? |e| RevivedShouldRejoinTheCount(Str.inspect(e))

	browser.close!()
}
