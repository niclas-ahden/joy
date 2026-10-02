# Real-browser E2E: DOM.focus in Chromium. The fake DOM can only record the
# call, so this is the coverage a real browser adds: the input revealed by
# the same update becomes document.activeElement, and keystrokes typed with
# no further click land in it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("focus", "#edit")?

	assert!(page.find("#name").not_exists())?

	# "Edit" -> update renders the input and returns DOM.focus("#name").
	page.find("#edit").click!()?
	assert!(page.find("#name").is_visible())?
	Assert.eq(focused_id!(page)?, "name") ? |e| InputShouldBeFocused(Str.inspect(e))

	# Typing at the page level, with no click on the input, goes into it,
	# and continues the value: the caret was put at the end.
	page.key_type_targetless!(" Lovelace")?
	assert!(page.find("#shown").has_text("Hello, Ada Lovelace"))?

	# A selector that matches nothing leaves focus where it was.
	page.find("#nothing").click!()?
	assert!(page.find("#missing").has_text("missing 1"))?
	Assert.eq(focused_id!(page)?, "nothing") ? |e| MissingSelectorShouldNotMoveFocus(Str.inspect(e))

	browser.close!()?
	Ok({})
}

# The id of the element that has keyboard focus.
focused_id! = |page|
	page.evaluate!("document.activeElement ? document.activeElement.id : ''")
