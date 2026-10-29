app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]
import spec.Assert

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "Buy milk")?
	TodoPage.add!(page, "Walk the dog")?

	TodoPage.edit!(page, 1)?
	assert!(page.find("${TodoPage.row(1)}.editing").is_visible()) ? |e| RowShouldEnterEditing(Str.inspect(e))
	edit_input = "${TodoPage.row(1)} .edit"
	assert!(page.find(edit_input).has_value("Buy milk")) ? |e| EditShouldStartFromTheTitle(Str.inspect(e))

	# The field has the keyboard already: what is typed next lands in it
	# without a click.
	focused = page.evaluate!("document.activeElement ? document.activeElement.className : ''")?
	Assert.eq(focused, "edit") ? |e| EditFieldShouldBeFocused(Str.inspect(e))
	page.key_type_targetless!("!")?
	assert!(page.find(edit_input).has_value("Buy milk!")) ? |e| TypingShouldLandInTheEditField(Str.inspect(e))

	# has_text normalizes whitespace on both sides, so it cannot see a
	# missing trim. Read the exact text instead.
	page.find(edit_input).fill!("  Buy oat milk  ")?
	page.key_press!(edit_input, Enter, [])?
	Assert.eq(page.find(TodoPage.label(1)).text!()?, "Buy oat milk") ? |e| CommitShouldTrimAndSave(Str.inspect(e))
	assert!(page.find_all(".todo-list li.editing").is_empty()) ? |e| EditingShouldEnd(Str.inspect(e))
	assert!(page.find(TodoPage.label(2)).has_text("Walk the dog")) ? |e| OtherTodosShouldBeUntouched(Str.inspect(e))

	browser.close!()
}
