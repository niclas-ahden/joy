app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

active_filter = ".filters li:nth-child(2) a"
completed_filter = ".filters li:nth-child(3) a"
all_filter = ".filters li:nth-child(1) a"

# Changing todos while a filter is on: the view updates right away, and
# every selector is positional, so the rows below shift up
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "One")?
	TodoPage.add!(page, "Two")?
	TodoPage.add!(page, "Three")?
	page.find(TodoPage.toggle(2)).check!()?

	# Completing a todo under Active drops it from the view
	page.find(active_filter).click!()?
	page.find(TodoPage.toggle(1)).check!()?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| CompletedShouldLeaveTheActiveView(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Three")) ? |e| TheRemainingActiveTodo(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("1 item left")) ? |e| CountShouldFollow(Str.inspect(e))

	# Editing under a filter edits the todo the view shows, not the
	# todo that happens to sit at that index in the full list
	page.find(completed_filter).click!()?
	assert!(page.find(TodoPage.label(1)).has_text("One")) ? |e| CompletedShouldShowBoth(Str.inspect(e))
	TodoPage.edit!(page, 1)?
	edit_input = "${TodoPage.row(1)} .edit"
	page.find(edit_input).fill!("One edited")?
	page.key_press!(edit_input, Enter, [])?
	assert!(page.find(TodoPage.label(1)).has_text("One edited")) ? |e| TheShownTodoShouldBeEdited(Str.inspect(e))

	# Back on All everything is still there, in order, with the edit applied
	page.find(all_filter).click!()?
	assert!(page.find_all(".todo-list li").has_count(3)) ? |e| AllShouldShowEverything(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("One edited")) ? |e| TheEditShouldStick(Str.inspect(e))
	assert!(page.find(TodoPage.label(2)).has_text("Two")) ? |e| SecondShouldBeUntouched(Str.inspect(e))
	assert!(page.find(TodoPage.label(3)).has_text("Three")) ? |e| ThirdShouldBeUntouched(Str.inspect(e))

	browser.close!()
}
