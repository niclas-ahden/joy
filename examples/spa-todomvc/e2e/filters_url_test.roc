app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# The filter links in footer order
active_filter = ".filters li:nth-child(2) a"

completed_filter = ".filters li:nth-child(3) a"

# The filter is part of the URL: a URL that names one opens with it on, a
# click on a filter lands in the URL, and Back returns to the one before.
main! = |_args| {
	# As a shared link or a refresh opens the app. The filters only show once
	# there is a todo.
	{ browser, page } = TodoPage.open_at!("/#/active")?
	TodoPage.add!(page, "One")?
	TodoPage.add!(page, "Two")?
	page.find(TodoPage.toggle(1)).check!()?
	assert!(page.find("${active_filter}.selected").is_visible()) ? |e| UrlShouldPickTheFilter(Str.inspect(e))
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| ActiveShouldHideCompleted(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Two")) ? |e| TheActiveTodo(Str.inspect(e))

	page.find(completed_filter).click!()?
	assert!(page.find("${completed_filter}[aria-current=page]").is_visible()) ? |e| SelectionShouldFollowTheClick(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("One")) ? |e| TheCompletedTodo(Str.inspect(e))
	clicked = page.evaluate!("location.hash")?
	if clicked != "#/completed" {
		return Err(ClickShouldLandInTheUrl(clicked))
	}

	# Back is the browser's too, and the todos are still there.
	_ = page.evaluate!("(history.back(), 'back')")?
	assert!(page.find("${active_filter}[aria-current=page]").is_visible()) ? |e| BackShouldReturnToTheFilter(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Two")) ? |e| BackShouldKeepTheTodos(Str.inspect(e))

	browser.close!()
}
