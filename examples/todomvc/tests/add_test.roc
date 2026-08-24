app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "Buy milk")?
	assert!(page.find(TodoPage.label(1)).has_text("Buy milk")) ? |e| TodoShouldBeListed(Str.inspect(e))
	assert!(page.find(".new-todo").has_value("")) ? |e| InputShouldClearForTheNextTodo(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("1 item left")) ? |e| CountShouldBeSingular(Str.inspect(e))

	TodoPage.add!(page, "Walk the dog")?
	assert!(page.find_all(".todo-list li").has_count(2)) ? |e| BothTodosShouldBeListed(Str.inspect(e))
	assert!(page.find(TodoPage.label(2)).has_text("Walk the dog")) ? |e| NewestTodoShouldBeLast(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("2 items left")) ? |e| CountShouldBePlural(Str.inspect(e))

	browser.close!()
}
