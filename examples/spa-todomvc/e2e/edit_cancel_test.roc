app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
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
