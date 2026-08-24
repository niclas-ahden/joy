app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# The three filter links in footer order
all_filter = ".filters li:nth-child(1) a"
active_filter = ".filters li:nth-child(2) a"
completed_filter = ".filters li:nth-child(3) a"

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "One")?
	TodoPage.add!(page, "Two")?
	TodoPage.add!(page, "Three")?
	page.find(TodoPage.toggle(2)).check!()?

	assert!(page.find("${all_filter}.selected").is_visible()) ? |e| AllShouldStartSelected(Str.inspect(e))

	page.find(active_filter).click!()?
	assert!(page.find_all(".todo-list li").has_count(2)) ? |e| ActiveShouldHideCompleted(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("One")) ? |e| FirstActiveTodo(Str.inspect(e))
	assert!(page.find(TodoPage.label(2)).has_text("Three")) ? |e| SecondActiveTodo(Str.inspect(e))
	assert!(page.find("${active_filter}.selected").is_visible()) ? |e| SelectionShouldFollowTheClick(Str.inspect(e))
	# The count is over all todos, not the filtered view
	assert!(page.find(".todo-count").has_text("2 items left")) ? |e| CountShouldIgnoreTheFilter(Str.inspect(e))

	page.find(completed_filter).click!()?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| CompletedShouldHideActive(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Two")) ? |e| TheCompletedTodo(Str.inspect(e))

	page.find(all_filter).click!()?
	assert!(page.find_all(".todo-list li").has_count(3)) ? |e| AllShouldShowEverything(Str.inspect(e))

	browser.close!()
}
