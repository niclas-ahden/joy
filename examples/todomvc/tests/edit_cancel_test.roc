app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
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
