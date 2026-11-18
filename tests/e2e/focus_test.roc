# Real-browser E2E: DOM.focus in Chromium. The fake DOM can only record the
# call, so this is the coverage a real browser adds: the input revealed by
# the same update becomes document.activeElement, and keystrokes typed with
# no further click land in it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
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
	focus_and_click!(page, "#nothing")?
	assert!(page.find("#missing").has_text("missing 1"))?
	Assert.eq(focused_id!(page)?, "nothing") ? |e| MissingSelectorShouldNotMoveFocus(Str.inspect(e))

	# A selector that is not valid CSS ("#12") matches nothing either, for
	# DOM.focus, show_modal and close_modal alike. The second click proves
	# the app is still running after the first.
	focus_and_click!(page, "#bad")?
	focus_and_click!(page, "#bad")?
	assert!(page.find("#invalid").has_text("invalid 2"))?
	Assert.eq(focused_id!(page)?, "bad") ? |e| InvalidSelectorShouldNotMoveFocus(Str.inspect(e))

	browser.close!()?
	Ok({})
}

# Focus a button and click it. WebKit on macOS does not focus a button that is
# clicked, as Safari does not, so a real click would leave the focus elsewhere
# there and prove nothing about the effect.
focus_and_click! = |page, selector| {
	_ = page.evaluate!("(document.querySelector('${selector}').focus(), document.querySelector('${selector}').click(), 'clicked')")?
	Ok({})
}

# The id of the element that has keyboard focus.
focused_id! = |page|
	page.evaluate!("document.activeElement ? document.activeElement.id : ''")
