app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "First")?
	TodoPage.add!(page, "Second")?

	TodoPage.destroy!(page, 1)?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| OneTodoShouldRemain(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Second")) ? |e| TheOtherTodoShouldRemain(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("1 item left")) ? |e| CountShouldFollow(Str.inspect(e))

	browser.close!()
}
