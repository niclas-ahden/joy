# Controlled form controls outside the simple case, in a real browser
# (tests/apps/controls.roc): a select controlled by its own value, value
# handlers on a wrapper instead of the control, one message per edit, and
# a value the model rewrites while the field is not focused. The fake-DOM
# harness (tests/check_controls.mjs) drives the composition orders.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("controls", "#rename")?

	# A select's value names an option, and the options are its children,
	# which a build creates after the select's own attributes. It must still
	# show the declared option, from the first paint and when the options
	# only arrive in a later render.
	assert!(page.find("#level").has_value("high"))?
	page.find("#load").click!()?
	assert!(page.find_all("#late option").has_count(3))?
	assert!(page.find("#late").has_value("high"))?

	# A value handler on a wrapper sees the control's event as it bubbles,
	# and a refused change must snap the control back all the same.
	page.fill!("#query", "ab")?
	assert!(page.find("#query").has_value("ab"))?
	page.key_press!("#query", Digit1, [Shift])?
	assert!(page.find("#query").has_value("ab"))?

	# The same for on_check: the update refuses unchecking. A plain click,
	# since Playwright's uncheck! verifies that the state flipped.
	page.click!("#agree")?
	assert!(page.find("#agree").is_checked())?

	# One edit is one message. Playwright's fill on Firefox ends a
	# composition before the input that carries the text.
	page.fill!("#search", "x")?
	assert!(page.find("#search").has_value("x"))?
	Assert.eq(settled_text!(page, "#searches")?, "searches 1") ? |e| OneEditShouldBeOneMessage(Str.inspect(e))

	# The model rewrites #title while the button has focus: the field must
	# not fire `select` (the app counts them, from boot on) or take focus.
	page.find("#rename").click!()?
	assert!(page.find("#title").has_value("Renamed 1"))?
	Assert.eq(settled_text!(page, "#selects")?, "selects 0") ? |e| ValueWriteShouldNotSelect(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.activeElement.id === 'title')")?, "false") ? |e| ValueWriteShouldNotFocus(Str.inspect(e))

	# #note commits on change, so its typing is not in the model yet. A
	# click inside it bubbles to the wrapper's on_click, which must leave
	# the field alone instead of pinning it back to the model's "".
	page.fill!("#note", "hello")?
	page.find("#note").click!()?
	assert!(page.find("#note-clicks").has_text("note clicks 1"))?
	assert!(page.find("#note").has_value("hello"))?

	# #swap names "b", which no option has until a render patches the first
	# option's value attribute to it. The select must then show that option.
	page.find("#swap-button").click!()?
	assert!(page.find("#swap").has_value("b"))?

	browser.close!()?
	Ok({})
}

# An element's text a moment from now, read once. A retrying claim would
# pass before an event the browser queues for later could change it.
settled_text! = |page, selector|
	page.evaluate!("new Promise((done) => setTimeout(() => done(document.querySelector('${selector}').textContent), 100))")
