app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
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
