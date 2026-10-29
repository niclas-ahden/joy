app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
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
