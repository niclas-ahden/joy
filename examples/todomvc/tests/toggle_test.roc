app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
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
