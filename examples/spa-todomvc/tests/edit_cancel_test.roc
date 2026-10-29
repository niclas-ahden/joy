app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "Keep me")?
	edit_input = "${TodoPage.row(1)} .edit"

	TodoPage.edit!(page, 1)?
	page.find(edit_input).fill!("Throw this away")?
	page.key_press!(edit_input, Escape, [])?
	assert!(page.find(TodoPage.label(1)).has_text("Keep me")) ? |e| EscapeShouldKeepTheTitle(Str.inspect(e))
	assert!(page.find_all(".todo-list li.editing").is_empty()) ? |e| EditingShouldEnd(Str.inspect(e))

	# The thrown-away draft must not leak into the next edit
	TodoPage.edit!(page, 1)?
	assert!(page.find(edit_input).has_value("Keep me")) ? |e| NextEditShouldStartFresh(Str.inspect(e))

	browser.close!()
}
