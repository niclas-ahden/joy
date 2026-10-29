# Real-browser E2E: DOM.focus in Chromium. The fake DOM can only record the
# call, so this is the coverage a real browser adds: the input revealed by
# the same update becomes document.activeElement, and keystrokes typed with
# no further click land in it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
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

	# A selector that is not valid CSS ("#12") matches nothing either, for
	# DOM.focus, show_modal and close_modal alike. The second click proves
	# the app is still running after the first.
	page.find("#bad").click!()?
	page.find("#bad").click!()?
	assert!(page.find("#invalid").has_text("invalid 2"))?
	Assert.eq(focused_id!(page)?, "bad") ? |e| InvalidSelectorShouldNotMoveFocus(Str.inspect(e))

	browser.close!()?
	Ok({})
}

# The id of the element that has keyboard focus.
focused_id! = |page|
	page.evaluate!("document.activeElement ? document.activeElement.id : ''")
