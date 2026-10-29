app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "One")?
	TodoPage.add!(page, "Two")?
	TodoPage.add!(page, "Three")?

	page.find(".toggle-all").check!()?
	assert!(page.find_all(".todo-list li.completed").has_count(3)) ? |e| AllShouldBeCompleted(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("0 items left")) ? |e| NothingShouldBeLeft(Str.inspect(e))

	page.find(".toggle-all").uncheck!()?
	assert!(page.find_all(".todo-list li.completed").is_empty()) ? |e| AllShouldBeActiveAgain(Str.inspect(e))
	assert!(page.find(".todo-count").has_text("3 items left")) ? |e| EverythingShouldBeLeft(Str.inspect(e))

	browser.close!()
}
